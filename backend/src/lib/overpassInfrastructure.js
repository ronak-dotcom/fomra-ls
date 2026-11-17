/**
 * Infrastructure scoring from OpenStreetMap via Overpass API.
 * Weights and distance penalties follow idea.txt (property evaluation spec).
 */

const POI_CATEGORIES = [
  // Education
  { name: 'Schools',          tag: 'amenity', value: 'school',          groups: ['education'] },
  { name: 'Colleges',         tag: 'amenity', value: 'college',         groups: ['education'] },
  { name: 'Universities',     tag: 'amenity', value: 'university',      groups: ['education'] },
  // Healthcare
  { name: 'Hospitals',        tag: 'amenity', value: 'hospital',        groups: ['health'] },
  { name: 'Clinics',          tag: 'amenity', value: 'clinic',          groups: ['health'] },
  { name: 'Pharmacies',       tag: 'amenity', value: 'pharmacy',        groups: ['health'] },
  // Transport
  { name: 'Bus Stops',        tag: 'highway', value: 'bus_stop',        groups: ['transport'] },
  { name: 'Bus Terminals',    tag: 'amenity', value: 'bus_station',     groups: ['transport'] },
  { name: 'Railway Stations', tag: 'railway', value: 'station',         groups: ['transport'], excludeSubway: true },
  { name: 'Metro Stations',   tag: 'railway', value: 'station',         groups: ['transport'], requireSubway: true },
  { name: 'Airports',         tag: 'aeroway', value: 'aerodrome',       groups: ['transport'] },
  // Commercial
  { name: 'Supermarkets',     tag: 'shop',    value: 'supermarket',     groups: ['commercial'] },
  { name: 'Banks',            tag: 'amenity', value: 'bank',            groups: ['commercial'] },
  { name: 'Malls',            tag: 'shop',    value: 'mall',            groups: ['commercial'] },
  { name: 'Restaurants',      tag: 'amenity', value: 'restaurant',      groups: ['commercial'] },
  { name: 'ATMs',             tag: 'amenity', value: 'atm',             groups: ['commercial'] },
  // Supplementary (display only — not in score formula)
  { name: 'IT Parks',         tag: 'office',  value: 'it',              groups: ['amenity'] },
  { name: 'Petrol Stations',  tag: 'amenity', value: 'fuel',            groups: ['amenity'] },
  { name: 'Govt. Offices',    tag: 'amenity', value: 'townhall',        groups: ['amenity'] },
  { name: 'Worship Places',   tag: 'amenity', value: 'place_of_worship', groups: ['amenity'] },
  // Site-context features behind the lead's automatic nearby notes. Scores are
  // computed from named categories only, so these never affect them.
  { name: 'Water Bodies',     tag: 'natural', value: 'water',           groups: ['siteContext'] },
  { name: 'Rivers & Canals',  tag: 'waterway', value: 'river',          groups: ['siteContext'] },
  { name: 'Cemeteries',       tag: 'landuse', value: 'cemetery',        groups: ['siteContext'] },
  { name: 'Graveyards',       tag: 'amenity', value: 'grave_yard',      groups: ['siteContext'] },
];

const HIGHWAY_TYPES = [
  'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
  'unclassified', 'residential', 'living_street',
];

const HIGHWAY_WEIGHT = {
  motorway:      4,
  trunk:         3.5,
  primary:       3,
  secondary:     2,
  tertiary:      1.5,
  unclassified:  1,
  residential:   0.6,
  living_street: 0.4,
};

/** Penalty per km: Score = max(0, 100 - distance × penalty) */
const DISTANCE_PENALTY = {
  school:      8,
  college:     7,
  university:  6,
  hospital:    10,
  clinic:      10,
  pharmacy:    8,
  supermarket: 7,
  bank:        8,
  mall:        7,
  restaurant:  6,
  atm:         5,
  bus:         5,
  railway:     5,
  metro:       6,
  airport:     4,
  highway:     6,
  mainRoad:    6,
};

function buildInfrastructureQuery(lat, lon, radiusMeters) {
  const area = `(around:${radiusMeters},${lat},${lon})`;
  const parts = [];

  for (const cat of POI_CATEGORIES) {
    const filter = `["${cat.tag}"="${cat.value}"]`;
    parts.push(`nwr${filter}${area};`);
  }

  for (const hw of HIGHWAY_TYPES) {
    parts.push(`way["highway"="${hw}"]${area};`);
  }

  return `[out:json][timeout:40];\n(\n${parts.join('\n')}\n);\nout tags center;`;
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const p = Math.PI / 180;
  const a = 0.5 - Math.cos((lat2 - lat1) * p) / 2
    + Math.cos(lat1 * p) * Math.cos(lat2 * p) * (1 - Math.cos((lon2 - lon1) * p)) / 2;
  return 2 * R * Math.asin(Math.sqrt(Math.max(0, a)));
}

function elementCoords(el) {
  if (el.lat != null && el.lon != null) {
    return { lat: Number(el.lat), lon: Number(el.lon) };
  }
  if (el.center?.lat != null && el.center?.lon != null) {
    return { lat: Number(el.center.lat), lon: Number(el.center.lon) };
  }
  return null;
}

function matchesCategory(tags, cat) {
  if (tags[cat.tag] !== cat.value) return false;
  if (cat.requireSubway && tags.station !== 'subway') return false;
  if (cat.excludeSubway && tags.station === 'subway') return false;
  return true;
}

function parseInfrastructureElements(elements, lat, lon) {
  const counts = {};
  const places = {};
  const roadCounts = {};
  const roadNearest = {};

  for (const cat of POI_CATEGORIES) {
    counts[cat.name] = 0;
    places[cat.name] = [];
  }
  for (const hw of HIGHWAY_TYPES) {
    roadCounts[hw] = 0;
    roadNearest[hw] = null;
  }

  for (const el of elements || []) {
    const tags = el.tags || {};
    const hw = tags.highway;
    if (hw && roadCounts[hw] !== undefined) {
      roadCounts[hw] += 1;
      const coords = elementCoords(el);
      if (coords) {
        const dist = haversineKm(lat, lon, coords.lat, coords.lon);
        if (roadNearest[hw] == null || dist < roadNearest[hw]) {
          roadNearest[hw] = dist;
        }
      }
      continue;
    }

    for (const cat of POI_CATEGORIES) {
      if (!matchesCategory(tags, cat)) continue;
      counts[cat.name] = (counts[cat.name] || 0) + 1;
      const name = String(tags.name || '').trim() || 'Unnamed';
      const coords = elementCoords(el);
      const entry = { name };
      if (coords) {
        entry.lat = coords.lat;
        entry.lon = coords.lon;
        entry.distance = Math.round(haversineKm(lat, lon, coords.lat, coords.lon) * 100) / 100;
      }
      places[cat.name].push(entry);
      break;
    }
  }

  for (const list of Object.values(places)) {
    list.sort((a, b) => (a.distance ?? 999) - (b.distance ?? 999));
  }

  return { counts, places, roadCounts, roadNearest };
}

function clampScore(value) {
  return Math.max(0, Math.min(100, Math.round(value * 10) / 10));
}

function nearestDistanceKm(places, categoryName) {
  const list = places[categoryName] || [];
  const withDist = list.filter((p) => p.distance != null);
  if (withDist.length === 0) return null;
  return Math.min(...withDist.map((p) => p.distance));
}

function nearestGroupKm(roadNearest, types) {
  let min = null;
  for (const t of types) {
    const d = roadNearest[t];
    if (d != null && (min == null || d < min)) min = d;
  }
  return min;
}

/** Continuous distance score from idea.txt */
function distanceScore(km, penalty, missingScore = 30) {
  if (km == null) return missingScore;
  return clampScore(Math.max(0, 100 - km * penalty));
}

/** Density score: how MANY of a type are nearby (each of the first 5 adds 20). */
const DENSITY_TARGET = 5;
function densityScore(count) {
  return clampScore((Math.min(count || 0, DENSITY_TARGET) / DENSITY_TARGET) * 100);
}

/**
 * Per-amenity score = 70% proximity (nearest one) + 30% density (how many).
 * So "1 close" scores well but "several close" scores higher.
 */
function amenityScore(nearestKm, count, penalty) {
  return clampScore(distanceScore(nearestKm, penalty) * 0.7 + densityScore(count) * 0.3);
}
function poiScore(places, category, penalty) {
  return amenityScore(
    nearestDistanceKm(places, category),
    (places[category] || []).length,
    penalty,
  );
}

function nearestBusKm(places) {
  const stop = nearestDistanceKm(places, 'Bus Stops');
  const terminal = nearestDistanceKm(places, 'Bus Terminals');
  if (stop == null) return terminal;
  if (terminal == null) return stop;
  return Math.min(stop, terminal);
}

function roadNetworkScore(roadCounts, radiusKm) {
  const major = ['motorway', 'trunk', 'primary', 'secondary', 'tertiary'];
  let weighted = 0;
  for (const hw of major) {
    weighted += (roadCounts[hw] || 0) * (HIGHWAY_WEIGHT[hw] || 1);
  }
  const maxW = radiusKm <= 2 ? 10 : radiusKm <= 5 ? 22 : 40;
  return clampScore((weighted / maxW) * 100);
}

function localTrafficScore(roadCounts, radiusKm) {
  const local = (roadCounts.tertiary || 0)
    + (roadCounts.unclassified || 0)
    + (roadCounts.residential || 0);
  const maxLocal = radiusKm <= 2 ? 8 : radiusKm <= 5 ? 18 : 35;
  return clampScore((local / maxLocal) * 100);
}

function educationScore(places) {
  const school = poiScore(places, 'Schools', DISTANCE_PENALTY.school);
  const college = poiScore(places, 'Colleges', DISTANCE_PENALTY.college);
  const university = poiScore(places, 'Universities', DISTANCE_PENALTY.university);
  return clampScore(school * 0.40 + college * 0.35 + university * 0.25);
}

function healthcareScore(places) {
  const hospital = poiScore(places, 'Hospitals', DISTANCE_PENALTY.hospital);
  const clinic = poiScore(places, 'Clinics', DISTANCE_PENALTY.clinic);
  const pharmacy = poiScore(places, 'Pharmacies', DISTANCE_PENALTY.pharmacy);
  return clampScore(hospital * 0.50 + clinic * 0.30 + pharmacy * 0.20);
}

function commercialScore(places) {
  const supermarket = poiScore(places, 'Supermarkets', DISTANCE_PENALTY.supermarket);
  const bank = poiScore(places, 'Banks', DISTANCE_PENALTY.bank);
  const mall = poiScore(places, 'Malls', DISTANCE_PENALTY.mall);
  const restaurant = poiScore(places, 'Restaurants', DISTANCE_PENALTY.restaurant);
  const atm = poiScore(places, 'ATMs', DISTANCE_PENALTY.atm);
  return clampScore(
    supermarket * 0.30
    + bank * 0.20
    + mall * 0.20
    + restaurant * 0.15
    + atm * 0.15,
  );
}

function transportScore(places) {
  const busCount = (places['Bus Stops'] || []).length
    + (places['Bus Terminals'] || []).length;
  const bus = amenityScore(nearestBusKm(places), busCount, DISTANCE_PENALTY.bus);
  const railway = poiScore(places, 'Railway Stations', DISTANCE_PENALTY.railway);
  const metro = poiScore(places, 'Metro Stations', DISTANCE_PENALTY.metro);
  const airport = poiScore(places, 'Airports', DISTANCE_PENALTY.airport);
  return clampScore(bus * 0.40 + railway * 0.30 + metro * 0.20 + airport * 0.10);
}

function roadWidthFromLeadFt(ft) {
  if (ft == null || !Number.isFinite(ft) || ft <= 0) return null;
  if (ft >= 40) return 100;
  if (ft >= 30) return 90;
  if (ft >= 20) return 75;
  if (ft >= 12) return 60;
  return 45;
}

function roadConnectivityScore(roadCounts, roadNearest, radiusKm, roadWidthFt) {
  const highway = distanceScore(
    nearestGroupKm(roadNearest, ['motorway', 'trunk']),
    DISTANCE_PENALTY.highway,
  );
  const mainRoad = distanceScore(
    nearestGroupKm(roadNearest, ['primary', 'secondary']),
    DISTANCE_PENALTY.mainRoad,
  );
  const roadWidth = roadWidthFromLeadFt(roadWidthFt) ?? roadNetworkScore(roadCounts, radiusKm);
  const traffic = localTrafficScore(roadCounts, radiusKm);
  return clampScore(highway * 0.40 + mainRoad * 0.30 + roadWidth * 0.20 + traffic * 0.10);
}

function computeInfrastructureScores(counts, places, roadCounts, roadNearest, radiusKm, roadWidthFt) {
  const education = educationScore(places);
  const healthcare = healthcareScore(places);
  const road = roadConnectivityScore(roadCounts, roadNearest, radiusKm, roadWidthFt);
  const commercial = commercialScore(places);
  const transport = transportScore(places);

  const overall = clampScore(
    education * 0.25
    + healthcare * 0.20
    + road * 0.25
    + commercial * 0.15
    + transport * 0.15,
  );

  return {
    Education:           education,
    Healthcare:          healthcare,
    'Road Connectivity': road,
    Commercial:          commercial,
    Transport:           transport,
    'Overall Location':  overall,
  };
}

module.exports = {
  POI_CATEGORIES,
  buildInfrastructureQuery,
  parseInfrastructureElements,
  computeInfrastructureScores,
};
