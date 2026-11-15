import 'dart:ui';

import 'package:material_ui/material_ui.dart' hide Route;
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
    runApp(
      ItineraryRenderer(
        encodedJourney: encodedJourney,
        showMap: true,//uri.queryParameters['showMap'] == '1',
        home: uri.queryParameters['home'] == null
            ? null
            : GeoPoint.fromString(uri.queryParameters['home']!),
      ),
    );
  } else {
    runApp(const Placeholder());
    return;
  }
}

class ItineraryRenderer extends StatefulWidget {
  const new({
    required this.encodedJourney,
    required this.showMap,
    required this.home,
    super.key,
  });
  final String encodedJourney;
  final bool showMap;
  final GeoPoint? home;
  @override
  State<ItineraryRenderer> createState() => _ItineraryRendererState();
}

class _ItineraryRendererState extends State<ItineraryRenderer> {
  Journey? journey;
  Map<DatasetID, GTFSDatasetWrapper> gtfs = {};
  MapController? controller;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse('https://treeplate.damowmow.com/gtfs_vta.zip'),
      ), // from https://gtfs.vta.org/gtfs_vta.zip, but copied onto my domain because of CORS issues
    ).then(
      (e) => setState(() {
        gtfs[.vta] = e;
        if (gtfs.length == 3) {
          journey = Journey.parse(widget.encodedJourney, gtfs);
        }
      }),
    );
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse('https://treeplate.damowmow.com/gtfs_vta.zip'),
      ), // from https://gtfs.vta.org/gtfs_vta.zip, but copied onto my domain because of CORS issues
    ).then(
      (e) => setState(() {
        gtfs[.vta] = e;
        if (gtfs.length == 3) {
          journey = Journey.parse(widget.encodedJourney, gtfs);
        }
      }),
    );
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse(
          'https://treeplate.damowmow.com/caltrain-ca-us.zip',
        ), // see above comment
      ),
    ).then(
      (e) => setState(() {
        gtfs[.caltrain] = e;
        if (gtfs.length == 3) {
          journey = Journey.parse(widget.encodedJourney, gtfs);
        }
      }),
    );
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse(
          'https://treeplate.damowmow.com/bart.zip',
        ), // see above comment
      ),
    ).then(
      (e) => setState(() {
        gtfs[.bart] = e;
        if (gtfs.length == 3) {
          journey = Journey.parse(widget.encodedJourney, gtfs);
        }
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
                  Text(
                    'ETA: ${gtfs[journey!.legs.last.dataset]!.stopTimesByTrip[journey!.legs.last.trip.id]!.singleWhere((e) => e.stopId == journey!.legs.last.end.id).arrivalTime!.toTimeString()} at ${journey!.legs.last.end.name}',
                  ),
                  if (widget.showMap)
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
                          DatasetID? currentLegDS;
                          for (Leg leg in journey!.legs) {
                            DateTime startTime = gtfs[leg.dataset]!
                                .stopTimesByTrip[leg.trip.id]!
                                .singleWhere((e) => e.stopId == leg.start.id)
                                .departureTime!
                                .relativeToDateTime(currentTime);
                            DateTime endTime = gtfs[leg.dataset]!
                                .stopTimesByTrip[leg.trip.id]!
                                .singleWhere((e) => e.stopId == leg.end.id)
                                .arrivalTime!
                                .relativeToDateTime(currentTime);
                            if (currentTime.isBefore(startTime)) {
                              if (lastLeg == null) {
                                beforeStart = true;
                              } else {
                                currentTrip = leg.trip;
                                currentLegStart = leg.start;
                                currentLegDS = leg.dataset;
                              }
                              break;
                            }
                            if (currentTime.isBefore(endTime)) {
                              currentTrip = leg.trip;
                              currentLegStart = leg.start;
                              currentLegDS = leg.dataset;
                              break;
                            }
                            lastLeg = leg;
                          }
                          StopTime? lastStop;
                          StopTime? nextStop;
                          double? t;
                          DatasetID? llds = currentLegDS;
                          if (currentTrip != null) {
                            for (StopTime stop
                                in gtfs[currentLegDS]!
                                    .stopTimesByTrip[currentTrip.id]!
                                    .skip(
                                      gtfs[currentLegDS]!
                                          .stopTimesByTrip[currentTrip.id]!
                                          .indexWhere(
                                            (e) =>
                                                e.stopId == currentLegStart!.id,
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
                                lastStop = gtfs[lastLeg!.dataset]!
                                    .stopTimesByTrip[lastLeg.trip.id]!
                                    .singleWhere(
                                      (e) => e.stopId == lastLeg!.end.id,
                                    );
                                llds = lastLeg.dataset;
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
                                  gtfs[llds]!.stops[lastStop!.stopId]!.latitude,
                                  gtfs[currentLegDS]!
                                      .stops[nextStop!.stopId]!
                                      .latitude,
                                  t,
                                )!;
                          double longitude = t == null
                              ? beforeStart
                                    ? journey!.legs.first.start.longitude!
                                    : journey!.legs.last.end.longitude!
                              : lerpDouble(
                                  gtfs[llds]!
                                      .stops[lastStop!.stopId]!
                                      .longitude,
                                  gtfs[currentLegDS]!
                                      .stops[nextStop!.stopId]!
                                      .longitude,
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
                              GeoPoint(
                                latitude: latitude,
                                longitude: longitude,
                              ),
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
                                  staticPoints: [
                                    if (widget.home != null)
                                      StaticPositionGeoPoint(
                                        'home',
                                        MarkerIcon(
                                          icon: Icon(
                                            Icons.home,
                                            color: Colors.black,
                                          ),
                                        ),
                                        [widget.home!],
                                      ),
                                  ],
                                ),
                              ),
                              Center(
                                child: Icon(Icons.person, color: Colors.black),
                              ),
                            ],
                          );
                        },
                      ),
                    )
                  else
                    for (Leg leg in journey!.legs)
                      Text(
                        '${leg.start.name} at ${gtfs[leg.dataset]!.stopTimesByTrip[leg.trip.id]!.singleWhere((e) => e.stopId == leg.start.id).departureTime!.toTimeString()} -> ${leg.dataset.name} ${leg.trip.routeId} -> ${leg.end.name} at ${gtfs[leg.dataset]!.stopTimesByTrip[leg.trip.id]!.singleWhere((e) => e.stopId == leg.end.id).arrivalTime!.toTimeString()}',
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
  String? home;
  Map<DatasetID, GTFSDatasetWrapper> gtfs = {};
  bool gtfsLoaded = false;

  @override
  void initState() {
    super.initState();
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse('https://treeplate.damowmow.com/gtfs_vta.zip'),
      ), // from https://gtfs.vta.org/gtfs_vta.zip, but copied onto my domain because of CORS issues
    ).then(
      (e) => setState(() {
        gtfs[.vta] = e;
      }),
    );
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse(
          'https://treeplate.damowmow.com/caltrain-ca-us.zip',
        ), // see above comment
      ),
    ).then(
      (e) => setState(() {
        gtfs[.caltrain] = e;
      }),
    );
    GTFSDatasetWrapper.load(
      DownloadableDataset(
        Uri.parse(
          'https://treeplate.damowmow.com/bart.zip',
        ), // see above comment
      ),
    ).then(
      (e) => setState(() {
        gtfs[.bart] = e;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: gtfs.isNotEmpty
            ? Column(
                children: [
                  SizedBox(
                    width: 500,
                    height: 50,
                    child: TextField(
                      onChanged: (value) {
                        setState(() {
                          home = value.isEmpty ? null : value;
                        });
                      },
                      decoration: InputDecoration(hintText: 'Home'),
                    ),
                  ),
                  for (MutableLeg leg in legs)
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          height: 50,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              DropdownButton(
                                hint: Text('Dataset'),
                                value: leg.dataset,
                                items: DatasetID.values
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (leg.dataset != value) {
                                    setState(() {
                                      leg.dataset = value;
                                      leg.route = null;
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
                              if (leg.dataset != null)
                                DropdownButton(
                                  hint: Text('Route'),
                                  value: leg.route,
                                  items: gtfs[leg.dataset]!.routes.values
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            '${e.shortName}: ${e.longName ?? 'no long name'}',
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
                                            gtfs[leg.dataset]!
                                                    .directions[(
                                                      directionID: e,
                                                      routeID: leg.route!.id,
                                                    )]
                                                    ?.directionName ??
                                                gtfs[leg.dataset]!
                                                    .directions[(
                                                      directionID: e,
                                                      routeID: leg.route!.id,
                                                    )]
                                                    ?.direction
                                                    .name ??
                                                'unknown direction',
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
                                  items: gtfs[leg.dataset]!.calendar.values
                                      .where(
                                        (Service service) =>
                                            gtfs[leg.dataset]!
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
                                        List<AStop> stops = gtfs[leg.dataset]!
                                            .getStopsForRoute(
                                              leg.route!,
                                              leg.direction!,
                                              leg.service!,
                                            );
                                        if (!stops.contains(leg.start)) {
                                          leg.start = null;
                                        }
                                        leg.trip = null;
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
                                  items: gtfs[leg.dataset]!
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
                                                !gtfs[leg.dataset]!
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
                                                  !gtfs[leg.dataset]!
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
                                            List<AStop> stops =
                                                gtfs[leg.dataset]!
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
                                  items:
                                      (gtfs[leg.dataset]!.trips.values
                                              .where(
                                                (e) =>
                                                    e.routeId ==
                                                        leg.route!.id &&
                                                    leg.direction ==
                                                        e.directionId &&
                                                    leg.service!.id ==
                                                        e.serviceId &&
                                                    gtfs[leg.dataset]!
                                                        .stopTimesByTrip[e.id]!
                                                        .any(
                                                          (e) =>
                                                              e.stopId ==
                                                              leg.start!.id,
                                                        ),
                                              )
                                              .toList()
                                            ..sort(
                                              (a, b) => gtfs[leg.dataset]!
                                                  .stopTimesByTrip[a.id]!
                                                  .singleWhere(
                                                    (e) =>
                                                        e.stopId ==
                                                        leg.start!.id,
                                                  )
                                                  .departureTime!
                                                  .relativeToDateTime(
                                                    DateTime.now(),
                                                  )
                                                  .compareTo(
                                                    gtfs[leg.dataset]!
                                                        .stopTimesByTrip[b.id]!
                                                        .singleWhere(
                                                          (e) =>
                                                              e.stopId ==
                                                              leg.start!.id,
                                                        )
                                                        .departureTime!
                                                        .relativeToDateTime(
                                                          DateTime.now(),
                                                        ),
                                                  ),
                                            ))
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text(
                                                gtfs[leg.dataset]!
                                                    .stopTimesByTrip[e.id]!
                                                    .singleWhere(
                                                      (e) =>
                                                          e.stopId ==
                                                          leg.start!.id,
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
                                                !gtfs[leg.dataset]!
                                                    .stopTimesByTrip[value.id]!
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
                                  items: gtfs[leg.dataset]!
                                      .stopTimesByTrip[leg.trip!.id]!
                                      .skip(
                                        gtfs[leg.dataset]!
                                            .stopTimesByTrip[leg.trip!.id]!
                                            .singleWhere(
                                              (e) => e.stopId == leg.start!.id,
                                            )
                                            .stopSequence,
                                      )
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: gtfs[leg.dataset]!
                                              .stops[e.stopId]!,
                                          child: Text(
                                            '${gtfs[leg.dataset]!.stops[e.stopId]!.name} (${e.arrivalTime!.toTimeString()})',
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
                  SelectableText(
                    'http://treeplate.damowmow.com/transit/?journey=${legs.map((e) => e.encode()).join('~')}${home == null ? '' : '&home=$home'}&showMap=1',
                  ),
                ],
              )
            : Text('Loading...'),
      ),
    );
  }
}
