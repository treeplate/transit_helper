# transit_helper

An app that uses GTFS data to let you plan a public transit journey, and track where you should be along that journey right now.

## Known issues

- Currently, only one transit agency is supported at a time, so you can't make a journey including multiple. This agency is currently hard-coded.
- This can't load any GTFS zip file that doesn't have a suitable CORS policy (hence why it currently fetches the file from treeplate.damowmow.com rather than gtfs.vta.org).
- This has only been tested with a few local transit agencies, and currently relies on the GTFS+ extension of directions.txt, and makes some assumptions about the ordering of the fields in directions.txt and stop_times.txt.
- It takes a while to load stop_times.txt.
- Between two stops, it just does a linear lerp, so if the path isn't actually a straight line it may look weird.
- There might be a weird bug regarding the current position at the start of a leg.
- Services are labeled by ID (which is pretty much an opaque number) and what days it runs on (which multiple services can have the same set of).