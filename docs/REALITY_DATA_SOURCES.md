# PUA Reality Data Sources

PUA treats external data as evidence, not decoration. The game must keep working offline, cache what it can, preserve source attribution, and never imply survey-grade accuracy from a feed that does not provide it.

## Already wired

- OpenStreetMap / Overpass: road geometry, building footprints, road names, signs, POIs and local map truth. OSM remains the main geographic/collision source.
- Open-Meteo Weather: temperature, rain, cloud, wind speed/direction, gusts and visibility drive lighting, fog, grip and atmosphere.
- Open-Meteo Air Quality: PM10, PM2.5, NO2 and AQI affect haze.
- Open-Meteo Marine: wave height, direction, period and sea temperature are available for coastal atmosphere.
- Postcodes.io: resolves the UK postcode centroid before a live OSM refresh. This is a postcode centroid, not a surveyed window/vehicle position.
- SEPA Time Series: Edinburgh Royal Botanic Gardens 15-minute observed rainfall is blended into road wetness so the road can be wet because it actually rained, not only because a forecast model says so.

## High-value next adapters

- KartaView public street imagery and sequence metadata: use as a source-labelled reference for facade/sign alignment and capture date. Do not silently turn arbitrary imagery into claimed geometry.
- Wikimedia/MediaWiki Geosearch: identify nearby notable places and geotagged images; use to raise landmark retention priority and as optional reference material with licence metadata.
- NaPTAN: precise public transport access points. Use for real bus-stop positions, names and identifiers.
- Scottish bus open data / SIRI or GTFS-Realtime: where an accessible feed exists, place buses on real routes and use real vehicle positions/service alerts.
- Traffic Scotland DATEX II: roadworks, unplanned events, traffic status, variable-message signs and journey times. Registration/approval is required, so keep this as an optional authenticated adapter.
- Traffic Scotland live traffic cameras: registered feed; useful for source-dated visual reference and weather/traffic validation, not direct texture scraping.
- OpenSky Network: live aircraft state vectors for the Edinburgh airspace. Use sparingly because anonymous access is rate limited; ideal for real aircraft presence/heading when a safe visual/audio representation is available.
- Ordnance Survey Data Hub: authoritative GB geospatial layers. OpenData is free; premium APIs require keys/plan limits. Use where it materially improves named features or geometry beyond OSM.
- SEPA river/tidal/rain stations: beyond the first rainfall adapter, use nearest-station observed rainfall, river/tidal level and quality-coded observations for water and wet-weather scenes.

## Rules

1. Cache every optional network feed and fail soft.
2. Keep data-source and timestamp metadata with derived game state.
3. Never replace a more authoritative geometry source with a weaker visual source.
4. Live data can alter traffic, weather, lighting, sound and transient objects, but must not move roads/buildings away from mapped truth.
5. Respect rate limits, terms, licences and required attribution.
6. For image-derived assets, record source URL, capture date, licence/permission and alignment status.
7. Low-spec builds use the same truth with fewer visible consequences, not invented substitute data.
