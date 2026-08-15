const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sourcePath = path.join(__dirname, '..', 'tools', 'DiscordPost.gs');
const source = fs.readFileSync(sourcePath, 'utf8');
assert.doesNotMatch(source, /const RAID_SPREADSHEET_ID\s*=/);
const documentProperties = new Map();
const testWorkbook = { getId: () => 'test-workbook-id' };
const context = vm.createContext({
  console,
  PropertiesService: {
    getDocumentProperties() {
      return {
        getProperty(name) { return documentProperties.get(name) || null; },
        setProperty(name, value) { documentProperties.set(name, value); }
      };
    }
  },
  SpreadsheetApp: {
    getActiveSpreadsheet: () => testWorkbook,
    openById: id => ({ openedWorkbookId: id })
  },
  Utilities: {
    base64Decode(value) {
      return Array.from(Buffer.from(value, 'base64'), byte => byte > 127 ? byte - 256 : byte);
    },
    newBlob(bytes, mimeType, name) {
      return {
        getBytes: () => bytes,
        getContentType: () => mimeType,
        getName: () => name
      };
    }
  }
});
vm.runInContext(source, context, { filename: sourcePath });

assert.equal(context.rememberBoundSpreadsheet_(), 'test-workbook-id');
assert.equal(
  documentProperties.get('PIZZA_WARRIORS_RAID_SPREADSHEET_ID'),
  'test-workbook-id'
);
assert.equal(context.getRaidSpreadsheet_().openedWorkbookId, 'test-workbook-id');

const rows = Array.from({ length: 109 }, (_, rowIndex) =>
  Array.from({ length: 19 }, (_, columnIndex) =>
    `R${rowIndex + 1}C${columnIndex + 1}`
  )
);

const validPlanRows = Array.from({ length: 79 }, () => ['']);
validPlanRows[0] = ['H1'];
validPlanRows[54] = ['BQL', 'COPY A55:Q62'];
validPlanRows[63] = ['H1'];
validPlanRows[75] = ['1st'];
validPlanRows[78] = ['4th'];
const validPlanTsv = validPlanRows.map(row => row.join('\t')).join('\n');

const atomicPlan = context.buildDesktopTsvPlan_({
  tsv: validPlanTsv,
  addonVersion: '1.1.0',
  planBundleId: 'bundle-2',
  planRevision: 2,
  planRosterHash: 'roster-abc',
  planSourceId: 'festergut-2',
  planReason: 'audible'
});
assert.equal(atomicPlan.planBundleId, 'bundle-2');
assert.equal(atomicPlan.planRevision, 2);
assert.equal(atomicPlan.planRosterHash, 'roster-abc');
assert.equal(atomicPlan.planSourceId, 'festergut-2');
assert.equal(atomicPlan.planReason, 'audible');
assert.throws(
  () => context.buildDesktopTsvPlan_({
    tsv: validPlanTsv,
    addonVersion: '1.1.0',
    planBundleId: 'bundle-incomplete',
    planRevision: 0
  }),
  /plan-bundle metadata is incomplete/
);
assert.equal(
  context.buildDesktopTsvPlan_({ tsv: validPlanTsv, addonVersion: '1.0.1' }).planRevision,
  0,
  'The protocol-2 endpoint remains compatible with a pre-1.1 desktop during deployment rollover.'
);

const updates = context.buildLiveRaidPlanUpdates_(rows);

assert.equal(updates.length, 5);
assert.equal(
  JSON.stringify(Array.from(updates, update => `${update.targetSheet}!${update.targetRange}`)),
  JSON.stringify([
    'Blood Prince Council!A6:F15',
    'Blood Prince Council!A20:F22',
    "Blood Queen Lana'Thel!A28:Q35",
    "Blood Queen Lana'Thel!N6:U15",
    "Blood Queen Lana'Thel!N20:T23"
  ])
);

assert.equal(updates[0].values[0][0], 'R1C1');
assert.equal(updates[0].values[9][5], 'R10C6');
assert.equal(updates[1].values[0][0], 'R13C1');
assert.equal(updates[1].values[2][5], 'R15C6');
assert.equal(updates[2].values[0][0], 'R55C1');
assert.equal(updates[2].values[7][16], 'R62C17');
assert.equal(updates[3].values[0][0], 'R64C1');
assert.equal(updates[3].values[9][7], 'R73C8');
assert.equal(updates[4].values[0][0], 'R76C1');
assert.equal(updates[4].values[3][6], 'R79C7');

const manifest = Array.from(context.getRaidExportManifest_(), value => ({
  safeName: value.safeName,
  targetWidth: value.targetWidth,
  expectedHeight: value.expectedHeight
}));
assert.deepEqual(manifest, [
  { safeName: 'blood_prince_council', targetWidth: 4096, expectedHeight: 1795 },
  { safeName: 'blood_queen_lanathel', targetWidth: 4096, expectedHeight: 2359 }
]);

const pngHeader = Array(24).fill(0);
[137, 80, 78, 71, 13, 10, 26, 10].forEach((value, index) => { pngHeader[index] = value; });
pngHeader[18] = 16;
pngHeader[22] = 7;
pngHeader[23] = 3;
assert.deepEqual(
  JSON.parse(JSON.stringify(context.readPngDimensionsFromBytes_(pngHeader))),
  { width: 4096, height: 1795 }
);

function encodedPngHeader(width, height) {
  const bytes = Array(24).fill(0);
  [137, 80, 78, 71, 13, 10, 26, 10].forEach((value, index) => { bytes[index] = value; });
  bytes[16] = (width >>> 24) & 255;
  bytes[17] = (width >>> 16) & 255;
  bytes[18] = (width >>> 8) & 255;
  bytes[19] = width & 255;
  bytes[20] = (height >>> 24) & 255;
  bytes[21] = (height >>> 16) & 255;
  bytes[22] = (height >>> 8) & 255;
  bytes[23] = height & 255;
  return Buffer.from(bytes).toString('base64');
}

const validated = context.validateRaidPngUploads_([
  { safeName: 'blood_prince_council', base64: encodedPngHeader(4096, 1795) },
  { safeName: 'blood_queen_lanathel', base64: encodedPngHeader(4096, 2359) }
]);
assert.equal(validated[0].getName(), 'blood_prince_council.png');
assert.equal(validated[1].getName(), 'blood_queen_lanathel.png');

const partialDiscordResponse = context.buildDiscordAttachmentDetails_({
  attachments: [
    {
      filename: 'blood_prince_council.png',
      width: 4096,
      height: 1795,
      size: 24
    }
  ]
}, validated);
assert.equal(partialDiscordResponse.confirmation, 'discord-http-2xx');
assert.equal(partialDiscordResponse.attachments.length, 2);
assert.equal(partialDiscordResponse.attachments[0].confirmedBy, 'discord-attachment');
assert.equal(partialDiscordResponse.attachments[1].confirmedBy, 'validated-upload');
assert.equal(partialDiscordResponse.attachments[1].width, 4096);
assert.equal(partialDiscordResponse.attachments[1].height, 2359);

const fullDiscordResponse = context.buildDiscordAttachmentDetails_({
  attachments: [
    { filename: 'blood_prince_council.png', width: 4096, height: 1795, size: 24 },
    { filename: 'blood_queen_lanathel.png', width: 4096, height: 2359, size: 24 }
  ]
}, validated);
assert.equal(fullDiscordResponse.confirmation, 'discord-attachments');

const recoveredPosting = context.buildConservativePostedState_({
  protocol: 2,
  fingerprint: 'known-plan',
  state: 'posting',
  startedAt: '2026-08-09T04:52:00.000Z',
  sourceWrittenAt: '2026-08-09T04:50:00.000Z',
  planBundleId: 'bundle-7',
  planRevision: 7,
  planRosterHash: 'roster-xyz',
  planSourceId: 'festergut-7',
  planReason: 'audible',
  liveSheets: ['Blood Prince Council!A6:F15']
});
assert.equal(recoveredPosting.state, 'posted');
assert.equal(recoveredPosting.fingerprint, 'known-plan');
assert.equal(recoveredPosting.publishedAt, '2026-08-09T04:52:00.000Z');
assert.equal(recoveredPosting.discordConfirmation, 'conservative-no-retry');
assert.equal(recoveredPosting.files.length, 2);
assert.equal(recoveredPosting.planBundleId, 'bundle-7');
assert.equal(recoveredPosting.planRevision, 7);
assert.equal(recoveredPosting.planSourceId, 'festergut-7');
assert.equal(recoveredPosting.planReason, 'audible');

assert.throws(
  () => context.validateRaidPngUploads_([
    { safeName: 'blood_prince_council', base64: encodedPngHeader(1024, 448) },
    { safeName: 'blood_queen_lanathel', base64: encodedPngHeader(1024, 589) }
  ]),
  /must be a native 4096px render/
);

assert.throws(
  () => context.publishRaidPlan_({}),
  /legacy 1024px publisher is disabled/
);

console.log('test_discord_post: PASS');
