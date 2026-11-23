// Bundle rev: resolve-map (force Vercel to rebuild this function so it
// picks up the latest backend/src/routes/competitors.js instead of a cached one).
const { createApiApp } = require('./_expressApp');
const router = require('../backend/src/routes/competitors');

module.exports = createApiApp('/api/competitors', router);
