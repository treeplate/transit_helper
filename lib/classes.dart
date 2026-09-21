import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:gtfs_bindings/schedule.dart';

enum Direction(final String name) {
  north("North"),
  south("South"),
  east("East"),
  west("West"),
  northeast("Northeast"),
  northwest("Northwest"),
  southeast("Southeast"),
  southwest("Southwest"),
  clockwise("Clockwise"),
  counterclockwise("Counterclockwise"),
  inbound("Inbound"),
  outbound("Outbound"),
  loop("Loop"),
  aLoop("A Loop"),
  bLoop("B Loop"),
}

/// from [GTFS+](https://www.transitwiki.org/TransitWiki/images/e/e7/GTFS%2B_Additional_Files_Format_Ver_1.7.pdf)
class DirectionEntry {
  final String routeID;
  final DirectionId directionID;
  final Direction direction;

  /// VTA extension, afaik undocumented
  final String? directionName;

  new({
    required this.routeID,
    required this.directionID,
    required this.direction,
    required this.directionName,
  });
}

enum Weekday(final String name) {
  monday('Monday'),
  tuesday('Tuesday'),
  wednesday('Wednesday'),
  thursday('Thursday'),
  friday('Friday'),
  saturday('Saturday'),
  sunday('Sunday'),
}

extension type ServiceWeekdays(final Set<Weekday> weekdays) {
  String get displayName =>
      weekdays.length == 5 &&
          weekdays.containsAll(
            Weekday.values.where((e) => e != .saturday && e != .sunday),
          )
      ? 'Weekday'
      : weekdays.length == 7
      ? 'All days'
      : weekdays.isEmpty
      ? 'Never'
      : weekdays.map((e) => e.name).join(', ');
}

class Service {
  final String id;
  final Date startDate;
  final Date endDate;
  final ServiceWeekdays weekdays;
  final List<Date> addedExceptions;
  final List<Date> removedExceptions;

  new({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.weekdays,
    required this.addedExceptions,
    required this.removedExceptions,
  });
}

class GTFSDatasetWrapper {
  late final Map<String, Trip> trips;
  late final Map<String, AStop> stops;
  late final Map<String, Route> routes;
  late final Map<String, Service> calendar;
  late final Map<({String routeID, DirectionId directionID}), DirectionEntry>
  directions;
  late final Map<String, List<StopTime>> stopTimesByTrip;
  late final Map<
    ({String routeID, DirectionId directionID, String serviceID}),
    List<StopTime>
  >
  stopTimesByRouteDirectionService;

  Future<void> load(GtfsDataset dataset) async {
    await dataset.pipe(tempDir: '/tmp');
    trips = Map.fromEntries(
      (await dataset.trips.listResource()).map((e) => MapEntry(e.id, e)),
    );
    print('loaded trips');
    stops = Map.fromEntries(
      (await dataset.stops.listResource()).map((e) => MapEntry(e.id, e)),
    );
    print('loaded stops');
    routes = Map.fromEntries(
      (await dataset.routes.listResource()).map((e) => MapEntry(e.id, e)),
    );
    print('loaded routes');
    calendar = {};
    for (RegularService service
        in await dataset.calendar.regularCalendar!.listResource()) {
      calendar[service.id] = Service(
        id: service.id,
        startDate: service.startDate,
        endDate: service.endDate,
        weekdays: ServiceWeekdays({
          if (service.monday == .available) .monday,
          if (service.tuesday == .available) .tuesday,
          if (service.wednesday == .available) .wednesday,
          if (service.thursday == .available) .thursday,
          if (service.friday == .available) .friday,
          if (service.saturday == .available) .saturday,
          if (service.sunday == .available) .sunday,
        }),
        addedExceptions: [],
        removedExceptions: [],
      );
    }
    for (OccasionalService service
        in await dataset.calendar.occasionalCalendar!.listResource()) {
      (switch (service.exceptionType) {
        ExceptionType.added => (calendar[service.id] ??= Service(
          id: service.id,
          startDate: Date(1, 1, 1),
          endDate: Date(1, 1, 1),
          weekdays: ServiceWeekdays({}),
          addedExceptions: [],
          removedExceptions: [],
        )).addedExceptions,
        ExceptionType.removed => calendar[service.id]!.removedExceptions,
      }).add(service.date);
    }
    print('loaded calendar');
    directions = Map.fromEntries(
      (await utf8.decoder
              .bind(
                (await dataset.getSource())
                    .singleWhere((e) => e.name == 'directions.txt')
                    .stream(),
              )
              .transform(csv.decoder)
              .toList())
          .skip(1)
          .map((entry) {
            return MapEntry(
              (
                directionID: DirectionId.forId(int.parse(entry[1])),
                routeID: entry[0] as String,
              ),
              DirectionEntry(
                routeID: entry[0] as String,
                directionID: DirectionId.forId(int.parse(entry[1])),
                direction:
                    Direction.values
                        .where((e) => e.name == entry[2])
                        .singleOrNull ??
                    () {
                      print('invalid direction ${entry[2]}');
                      Direction? nocaps = Direction.values
                          .where(
                            (e) =>
                                e.name.toLowerCase() ==
                                (entry[2] as String).toLowerCase(),
                          )
                          .singleOrNull;
                      return nocaps ?? Direction.aLoop;
                    }(),
                directionName: entry.length < 4 ? null : entry[3],
              ),
            );
          })
          .toList(),
    );
    print('loaded directions');
    Stopwatch stopwatch = Stopwatch();
    stopwatch.start();
    List<List<String>> rawStopTimes = (await utf8.decoder
        .bind(
          (await dataset.getSource())
              .singleWhere((e) => e.name == 'stop_times.txt')
              .stream(),
        )
        .transform(csv.decoder)
        .map((e) => e.cast<String>())
        .toList());
    print('loaded stop times: ${stopwatch.elapsed}');
    stopwatch.reset();
    stopTimesByTrip = {};
    stopTimesByRouteDirectionService = {};
    for (List<String> rawStopTime in rawStopTimes.skip(1)) {
      StopTime stopTime = StopTime(
        tripId: rawStopTime[0],
        arrivalTime: rawStopTimes.first[1] == 'arrival_time'
            ? Time.parse(rawStopTime[1])
            : Time.parse(rawStopTime[2]),
        departureTime: rawStopTimes.first[2] == 'departure_time'
            ? Time.parse(rawStopTime[2])
            : Time.parse(rawStopTime[3]),
        stopId: rawStopTimes.first[1] == 'stop_id'
            ? rawStopTime[1]
            : rawStopTime[3],
        locationGroupId: null,
        locationId: null,
        stopSequence: int.parse(rawStopTime[4]),
        stopHeadsign: rawStopTime[5],
        startPickupDropOffWindow: null,
        endPickupDropOffWindow: null,
        pickupType:
            rawStopTime[6] == '' || !rawStopTimes.first.contains('pickup_type')
            ? null
            : PickupType.forId(int.parse(rawStopTime[6])),
        dropOffType:
            rawStopTime[7] == '' || !rawStopTimes.first.contains('dropoff_type')
            ? null
            : DropOffType.forId(int.parse(rawStopTime[7])),
        continuousPickup: null,
        continuousDropOff: null,
        shapeDistTraveled: rawStopTimes.first.contains('pickup_type')
            ? double.tryParse(rawStopTime[8])
            : double.tryParse(rawStopTime[6]),
        timepoint: rawStopTimes.first.contains('pickup_type')
            ? rawStopTime.length > 9
                  ? Timepoint.forId(int.parse(rawStopTime[9]))
                  : null
            : Timepoint.forId(int.parse(rawStopTime[7])),
        pickupBookingRuleId: null,
        dropOffBookingRuleId: null,
      );
      (stopTimesByRouteDirectionService[(
                routeID: trips[stopTime.tripId]!.routeId,
                directionID: trips[stopTime.tripId]!.directionId!,
                serviceID: trips[stopTime.tripId]!.serviceId,
              )] ??=
              [])
          .add(stopTime);
      (stopTimesByTrip[stopTime.tripId] ??= []).add(stopTime);
    }
    for (List<StopTime> trip in stopTimesByTrip.values) {
      trip.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }
    print('saved stop times: ${stopwatch.elapsed}');
  }

  List<AStop> getStopsForRoute(
    Route route,
    DirectionId direction,
    Service service,
  ) {
    Map<String, int> sequence = {};
    for ((String, int) stop
        in stopTimesByRouteDirectionService[(
              routeID: route.id,
              directionID: direction,
              serviceID: service.id,
            )]!
            .map((e) => (e.stopId!, e.stopSequence))) {
      if (sequence[stop.$1] == null || sequence[stop.$1]! < stop.$2) {
        sequence[stop.$1] = stop.$2;
      }
    }
    return (sequence.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value)))
        .map((e) => stops[e.key]!)
        .toList();
  }
}

class Journey {
  final List<Leg> legs;

  new({required this.legs});
  factory Journey.parse(String encodedJourney, GTFSDatasetWrapper gtfs) {
    return Journey(
      legs: encodedJourney.split('~').map((e) => Leg.parse(e, gtfs)).toList(),
    );
  }
}

class MutableLeg {
  Route? route;
  DirectionId? direction;
  Service? service;
  AStop? start;
  Trip? trip;
  AStop? end;

  String encode() => '${trip?.id}_${start?.id}-${end?.id}';
}

class Leg {
  final Trip trip;
  final AStop start;
  final AStop end;

  new({required this.trip, required this.start, required this.end});

  factory Leg.parse(String encodedLeg, GTFSDatasetWrapper gtfs) {
    return Leg(
      trip: gtfs.trips[encodedLeg.substring(0, encodedLeg.indexOf('_'))]!,
      start:
          gtfs.stops[encodedLeg.substring(
            encodedLeg.indexOf('_') + 1,
            encodedLeg.indexOf('-'),
          )]!,
      end: gtfs.stops[encodedLeg.substring(encodedLeg.indexOf('-') + 1)]!,
    );
  }
}

extension Stringify on Time {
  String toTimeString() =>
      '$hour:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
}
