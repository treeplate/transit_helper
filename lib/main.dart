import 'dart:ui';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:gtfs_bindings/schedule.dart';
import 'package:transit_helper/ui_core.dart';

import 'classes.dart';

void main() {
  Uri uri = Uri.base;
  String mode = uri.queryParameters['mode'] ?? 'itinerary';
  if (mode == 'itinerary') {
    String? encodedJourney = uri.queryParameters['journey'];
    if (encodedJourney == null) {
      runApp(const ItineraryCreator());
      return;
    }
    runApp(ItineraryRenderer(encodedJourney: encodedJourney));
  } else {
    runApp(const Placeholder());
    return;
  }
}

class ItineraryRenderer extends StatefulWidget {
  const new({required this.encodedJourney, super.key});
  final String encodedJourney;
  @override
  State<ItineraryRenderer> createState() => _ItineraryRendererState();
}

class _ItineraryRendererState extends State<ItineraryRenderer> {
  Journey? journey;
  GTFSDatasetWrapper gtfs = GTFSDatasetWrapper();
  MapController? controller;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    gtfs
        .load(
          DownloadableDataset(
            Uri.parse('https://treeplate.damowmow.com/gtfs_vta.zip'),
          ), // from https://gtfs.vta.org/gtfs_vta.zip, but copied onto my domain because of CORS issues
        )
        .then(
          (e) => setState(() {
            journey = Journey.parse(widget.encodedJourney, gtfs);
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: journey == null
            ? Text('Loading...')
            : Column(
                children: [
                  for (Leg leg in journey!.legs)
                    Text(
                      '${leg.trip.routeId} ${leg.trip.tripHeadsign} from ${leg.start.name} at ${gtfs.stopTimesByTrip[leg.trip.id]!.singleWhere((e) => e.stopId == leg.start.id).departureTime!.toTimeString()} to ${leg.end.name} at ${gtfs.stopTimesByTrip[leg.trip.id]!.singleWhere((e) => e.stopId == leg.end.id).arrivalTime!.toTimeString()}',
                    ),
                  Expanded(
                    child: ContinuousBuilder(
                      builder: (context) {
                        DateTime currentTime = DateTime.now().copyWith(
                          minute: DateTime.now().minute,
                        );
                        Trip? currentTrip;
                        AStop? currentLegStart;
                        bool beforeStart = false;
                        Leg? lastLeg;
                        for (Leg leg in journey!.legs) {
                          DateTime startTime = gtfs
                              .stopTimesByTrip[leg.trip.id]!
                              .singleWhere((e) => e.stopId == leg.start.id)
                              .departureTime!
                              .relativeToDateTime(currentTime);
                          DateTime endTime = gtfs.stopTimesByTrip[leg.trip.id]!
                              .singleWhere((e) => e.stopId == leg.end.id)
                              .arrivalTime!
                              .relativeToDateTime(currentTime);
                          if (currentTime.isBefore(startTime)) {
                            if (lastLeg == null) {
                              beforeStart = true;
                            } else {
                              currentTrip = leg.trip;
                              currentLegStart = leg.start;
                            }
                            break;
                          }
                          if (currentTime.isBefore(endTime)) {
                            currentTrip = leg.trip;
                            currentLegStart = leg.start;
                            break;
                          }
                          lastLeg = leg;
                        }
                        StopTime? lastStop;
                        StopTime? nextStop;
                        double? t;
                        if (currentTrip != null) {
                          for (StopTime stop
                              in gtfs.stopTimesByTrip[currentTrip.id]!.skip(
                                gtfs.stopTimesByTrip[currentTrip.id]!
                                    .indexWhere(
                                      (e) => e.stopId == currentLegStart!.id,
                                    ),
                              )) {
                            DateTime arrivalTime = stop.arrivalTime!
                                .relativeToDateTime(currentTime);
                            if (lastStop == null &&
                                currentTime.isBefore(
                                  stop.departureTime!.relativeToDateTime(
                                    currentTime,
                                  ),
                                )) {
                              lastStop = gtfs.stopTimesByTrip[lastLeg!.trip.id]!
                                  .singleWhere(
                                    (e) => e.stopId == lastLeg!.end.id,
                                  );
                              nextStop = stop;
                              t =
                                  (currentTime
                                      .difference(
                                        lastStop.arrivalTime!
                                            .relativeToDateTime(currentTime),
                                      )
                                      .inMilliseconds) /
                                  stop.departureTime!
                                      .relativeToDateTime(currentTime)
                                      .difference(
                                        lastStop.arrivalTime!
                                            .relativeToDateTime(currentTime),
                                      )
                                      .inMilliseconds;
                              break;
                            }
                            if (currentTime.isBefore(arrivalTime)) {
                              lastStop ??= stop;
                              nextStop = stop;
                              t =
                                  (currentTime
                                      .difference(
                                        lastStop.departureTime!
                                            .relativeToDateTime(currentTime),
                                      )
                                      .inMilliseconds) /
                                  arrivalTime
                                      .difference(
                                        lastStop.departureTime!
                                            .relativeToDateTime(currentTime),
                                      )
                                      .inMilliseconds;
                              break;
                            }
                            lastStop = stop;
                          }
                        }
                        double latitude = t == null
                            ? beforeStart
                                  ? journey!.legs.first.start.latitude!
                                  : journey!.legs.last.end.latitude!
                            : lerpDouble(
                                gtfs.stops[lastStop!.stopId]!.latitude,
                                gtfs.stops[nextStop!.stopId]!.latitude,
                                t,
                              )!;
                        double longitude = t == null
                            ? beforeStart
                                  ? journey!.legs.first.start.longitude!
                                  : journey!.legs.last.end.longitude!
                            : lerpDouble(
                                gtfs.stops[lastStop!.stopId]!.longitude,
                                gtfs.stops[nextStop!.stopId]!.longitude,
                                t,
                              )!;
                        /*
                        );*/
                        controller ??= MapController(
                          initPosition: GeoPoint(
                            latitude: latitude,
                            longitude: longitude,
                          ),
                        );
                        if (ready) {
                          controller!.moveTo(
                            GeoPoint(latitude: latitude, longitude: longitude),
                          );
                        }
                        return Stack(
                          children: [
                            OSMFlutter(
                              controller: controller!,
                              onMapIsReady: (p0) {
                                ready = true;
                              },
                              osmOption: OSMOption(
                                zoomOption: ZoomOption(initZoom: 13),
                              ),
                            ),
                            Center(
                              child: Icon(Icons.person, color: Colors.black),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ItineraryCreator extends StatefulWidget {
  const new({super.key});

  @override
  State<ItineraryCreator> createState() => _ItineraryCreatorState();
}

class _ItineraryCreatorState extends State<ItineraryCreator> {
  List<MutableLeg> legs = [MutableLeg()];
  GTFSDatasetWrapper gtfs = GTFSDatasetWrapper();
  bool gtfsLoaded = false;

  @override
  void initState() {
    super.initState();
    gtfs
        .load(
          DownloadableDataset(
            Uri.parse('https://treeplate.damowmow.com/gtfs_vta.zip'),
          ), // from https://gtfs.vta.org/gtfs_vta.zip, but copied onto my domain because of CORS issues
        )
        .then(
          (e) => setState(() {
            gtfsLoaded = true;
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: gtfsLoaded
            ? Column(
                children: [
                  for (MutableLeg leg in legs)
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          height: 50,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              DropdownButton(
                                hint: Text('Route'),
                                value: leg.route,
                                items: gtfs.routes.values
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          '${e.shortName}: ${e.longName}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (leg.route != value) {
                                    setState(() {
                                      leg.route = value;
                                      leg.direction = null;
                                      leg.service = null;
                                      leg.start = null;
                                      leg.trip = null;
                                      leg.end = null;
                                    });
                                  }
                                },
                              ),
                              SizedBox(width: 16),
                              if (leg.route != null)
                                DropdownButton(
                                  value: leg.direction,
                                  hint: Text('Direction'),
                                  items: DirectionId.values
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            '${gtfs.directions[(directionID: e, routeID: leg.route!.id)]!.directionName}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (leg.direction != value) {
                                      setState(() {
                                        leg.direction = value;
                                        leg.service = null;
                                        leg.start = null;
                                        leg.trip = null;
                                        leg.end = null;
                                      });
                                    }
                                  },
                                ),
                              SizedBox(width: 16),
                              if (leg.route != null && leg.direction != null)
                                DropdownButton(
                                  value: leg.service,
                                  hint: Text('Service'),
                                  items: gtfs.calendar.values
                                      .where(
                                        (Service service) =>
                                            gtfs
                                                .stopTimesByRouteDirectionService[(
                                                  routeID: leg.route!.id,
                                                  directionID: leg.direction!,
                                                  serviceID: service.id,
                                                )]
                                                ?.isNotEmpty ??
                                            false,
                                      )
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            '${e.id} - ${e.weekdays.displayName}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (leg.service != value) {
                                      setState(() {
                                        leg.service = value;
                                        leg.start = null;
                                        leg.trip = null;
                                        leg.end = null;
                                      });
                                    }
                                  },
                                ),
                              SizedBox(width: 16),
                              if (leg.route != null &&
                                  leg.direction != null &&
                                  leg.service != null)
                                DropdownButton(
                                  value: leg.start,
                                  hint: Text('Start'),
                                  items: gtfs
                                      .getStopsForRoute(
                                        leg.route!,
                                        leg.direction!,
                                        leg.service!,
                                      )
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text('${e.name}'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (leg.start != value) {
                                      setState(() {
                                        leg.start = value;
                                        if (value == null ||
                                            leg.trip != null &&
                                                !gtfs
                                                    .stopTimesByTrip[leg
                                                        .trip
                                                        ?.id]!
                                                    .any(
                                                      (e) =>
                                                          e.stopId == value.id,
                                                    )) {
                                          leg.trip = null;
                                        }
                                        if (leg.end != null) {
                                          if (value == null ||
                                              (leg.trip != null &&
                                                  !gtfs
                                                      .stopTimesByTrip[leg
                                                          .trip
                                                          ?.id]!
                                                      .any(
                                                        (e) =>
                                                            e.stopId ==
                                                            leg.end!.id,
                                                      ))) {
                                            leg.end = null;
                                          } else {
                                            List<AStop> stops = gtfs
                                                .getStopsForRoute(
                                                  leg.route!,
                                                  leg.direction!,
                                                  leg.service!,
                                                );
                                            if (!stops
                                                .skip(stops.indexOf(value))
                                                .contains(leg.end)) {
                                              leg.end = null;
                                            }
                                          }
                                        }
                                      });
                                    }
                                  },
                                ),
                              SizedBox(width: 16),
                              if (leg.route != null &&
                                  leg.direction != null &&
                                  leg.service != null &&
                                  leg.start != null)
                                DropdownButton(
                                  value: leg.trip,
                                  hint: Text('Time'),
                                  items: gtfs.trips.values
                                      .where(
                                        (e) =>
                                            e.routeId == leg.route!.id &&
                                            leg.direction == e.directionId &&
                                            leg.service!.id == e.serviceId &&
                                            gtfs.stopTimesByTrip[e.id]!.any(
                                              (e) => e.stopId == leg.start!.id,
                                            ),
                                      )
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            gtfs.stopTimesByTrip[e.id]!
                                                .singleWhere(
                                                  (e) =>
                                                      e.stopId == leg.start!.id,
                                                )
                                                .departureTime!
                                                .toTimeString(),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (leg.trip != value) {
                                      setState(() {
                                        leg.trip = value;
                                        if (value == null ||
                                            leg.end != null &&
                                                !gtfs.stopTimesByTrip[value.id]!
                                                    .any(
                                                      (e) =>
                                                          e.stopId ==
                                                          leg.end!.id,
                                                    )) {
                                          leg.end = null;
                                        }
                                      });
                                    }
                                  },
                                ),
                              SizedBox(width: 16),
                              if (leg.start != null && leg.trip != null)
                                DropdownButton(
                                  value: leg.end,
                                  hint: Text('End'),
                                  items: gtfs.stopTimesByTrip[leg.trip!.id]!
                                      .skip(
                                        gtfs.stopTimesByTrip[leg.trip!.id]!
                                            .singleWhere(
                                              (e) => e.stopId == leg.start!.id,
                                            )
                                            .stopSequence,
                                      )
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: gtfs.stops[e.stopId]!,
                                          child: Text(
                                            '${gtfs.stops[e.stopId]!.name} (${e.arrivalTime!.toTimeString()})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (e) {
                                    setState(() {
                                      leg.end = e;
                                    });
                                  },
                                ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    legs.remove(leg);
                                  });
                                },
                                icon: Icon(Icons.delete),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        legs.add(MutableLeg());
                      });
                    },
                    icon: Icon(Icons.add),
                  ),
                  SelectableText(legs.map((e) => e.encode()).join('~')),
                ],
              )
            : Text('Loading...'),
      ),
    );
  }
}
