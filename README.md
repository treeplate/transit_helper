# transit_helper

An app that uses GTFS data to let you plan a public transit journey, and track where you should be along that journey right now.

## Known issues

- Currently, only one transit agency is supported at a time, so you can't make a journey including multiple. This agency is currently hard-coded.
- This can't load any GTFS zip file that doesn't have a suitable CORS policy.
- This has only been tested with VTA so far, and currently relies on the GTFS+ extension of directions.txt.
- It takes a while to load stop_times.txt.