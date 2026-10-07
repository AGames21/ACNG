// Print every command the ACNG Assists buttons can send, for test_assists_bridge.py.
const view = require('../beamng-mod/ui/modules/apps/ACNGAssists/app.js');
const out = [];
for (const key of ['abs', 'tc']) for (const choice of ['factory', 0, 1, 2, 3]) out.push([key, choice, view.command(key, choice)]);
process.stdout.write(JSON.stringify(out));
