const DISCORD_WEBHOOK_PROPERTY = 'RAID_POSITIONS_DISCORD_WEBHOOK';
const DESKTOP_TSV_TOKEN_PROPERTY = 'PIZZA_WARRIORS_DESKTOP_TSV_TOKEN';
const RAID_SPREADSHEET_ID_PROPERTY = 'PIZZA_WARRIORS_RAID_SPREADSHEET_ID';
const TSV_DUMP_SHEET_NAME = 'WoW TSV Dump';
const TSV_DUMP_CLEAR_ROWS = 250;
const TSV_DUMP_CLEAR_COLUMNS = 26;
const LAST_PUBLISH_STATE_PROPERTY = 'PIZZA_WARRIORS_LAST_PUBLISH_STATE';
const RAID_PUBLISH_PROTOCOL_VERSION = 2;
const RAID_PNG_TARGET_WIDTH = 4096;
const RAID_PNG_MAX_BYTES = 10 * 1024 * 1024;
const RAID_PDF_PAGE_WIDTH_POINTS = 842;
const RAID_PDF_PAGE_HEIGHT_POINTS = 595;

const LIVE_PLAN_BLOCKS = [
  {
    label: 'BPC positions',
    sourceRow: 1,
    sourceColumn: 1,
    rows: 10,
    columns: 6,
    targetSheet: 'Blood Prince Council',
    targetRange: 'A6:F15'
  },
  {
    label: 'BPC ability rotations',
    sourceRow: 13,
    sourceColumn: 1,
    rows: 3,
    columns: 6,
    targetSheet: 'Blood Prince Council',
    targetRange: 'A20:F22'
  },
  {
    label: 'BQL bite order',
    sourceRow: 55,
    sourceColumn: 1,
    rows: 8,
    columns: 17,
    targetSheet: "Blood Queen Lana'Thel",
    targetRange: 'A28:Q35'
  },
  {
    label: 'BQL positions',
    sourceRow: 64,
    sourceColumn: 1,
    rows: 10,
    columns: 8,
    targetSheet: "Blood Queen Lana'Thel",
    targetRange: 'N6:U15'
  },
  {
    label: 'BQL ability rotations',
    sourceRow: 76,
    sourceColumn: 1,
    rows: 4,
    columns: 7,
    targetSheet: "Blood Queen Lana'Thel",
    targetRange: 'N20:T23'
  }
];

const RAID_EXPORTS = [
  {
    label: 'Blood Prince Council',
    sheetName: 'Blood Prince Council',
    rangeA1: 'A1:R39',
    safeName: 'blood_prince_council',
    cropBottomPoints: 226,
    targetWidth: RAID_PNG_TARGET_WIDTH
  },
  {
    label: "Blood Queen Lana'Thel",
    sheetName: "Blood Queen Lana'Thel",
    rangeA1: 'A1:U35',
    safeName: 'blood_queen_lanathel',
    cropBottomPoints: 110,
    targetWidth: RAID_PNG_TARGET_WIDTH
  }
];

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Raid Positions')
    .addItem('Set Discord webhook', 'setDiscordWebhook')
    .addItem('Configure desktop TSV sync', 'configureDesktopTsvSync')
    .addSeparator()
    .addItem('Preview raid layout', 'previewRaidPngs')
    .addItem('About 4K Discord publishing', 'postRaidPngsToDiscord')
    .addToUi();
}

function configureDesktopTsvSync() {
  rememberBoundSpreadsheet_();
  const properties = PropertiesService.getDocumentProperties();
  let token = properties.getProperty(DESKTOP_TSV_TOKEN_PROPERTY);

  if (!token) {
    token = (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, '');
    properties.setProperty(DESKTOP_TSV_TOKEN_PROPERTY, token);
  }

  const deploymentUrl = ScriptApp.getService().getUrl() || '';
  const html = HtmlService
    .createHtmlOutput(buildDesktopSyncSetupHtml_(deploymentUrl, token))
    .setWidth(660)
    .setHeight(390);

  SpreadsheetApp.getUi().showModalDialog(html, 'Pizza Warriors desktop TSV sync');
}

function rememberBoundSpreadsheet_() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    throw new Error('Open the bound raid-position workbook before running first-time setup.');
  }

  PropertiesService
    .getDocumentProperties()
    .setProperty(RAID_SPREADSHEET_ID_PROPERTY, spreadsheet.getId());
  return spreadsheet.getId();
}

function getRaidSpreadsheet_() {
  const spreadsheetId = PropertiesService
    .getDocumentProperties()
    .getProperty(RAID_SPREADSHEET_ID_PROPERTY);

  if (!spreadsheetId) {
    throw new Error('This workbook is not bound to the desktop publisher. Open Raid Positions > Configure desktop TSV sync once, then retry.');
  }

  return SpreadsheetApp.openById(spreadsheetId);
}

function buildDesktopSyncSetupHtml_(deploymentUrl, token) {
  const urlValue = deploymentUrl || 'Deploy this project as a Web app first, then reopen this dialog.';
  const ready = Boolean(deploymentUrl);

  return `
    <!doctype html>
    <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; margin: 22px; color: #111827; }
          h2 { margin: 0 0 12px; color: #1f4e79; }
          p { line-height: 1.45; }
          label { display: block; margin: 16px 0 6px; font-weight: 700; }
          .row { display: flex; gap: 8px; }
          input { flex: 1; padding: 9px; font-family: Consolas, monospace; }
          button { padding: 9px 14px; border: 0; border-radius: 4px; background: #1f4e79; color: #fff; font-weight: 700; cursor: pointer; }
          .status { margin-top: 14px; font-weight: 700; color: ${ready ? '#166534' : '#991b1b'}; }
          .small { font-size: 12px; color: #4b5563; }
        </style>
      </head>
      <body>
        <h2>One-time desktop setup</h2>
        <p>The desktop launcher reads the latest flushed PizzaRaidPlanner TSV, updates only the managed raid-plan cells, renders both vector sheets as crisp 4K PNGs on Windows, and posts those exact files to Discord.</p>
        <label>Web app URL</label>
        <div class="row"><input id="url" readonly value="${escapeHtml_(urlValue)}"><button onclick="copyField('url')">Copy</button></div>
        <label>Private upload token</label>
        <div class="row"><input id="token" readonly value="${escapeHtml_(token)}"><button onclick="copyField('token')">Copy</button></div>
        <div class="status">${ready ? 'Ready to enter these two values into the desktop launcher.' : 'Deployment required: Deploy > New deployment > Web app; execute as you; access Anyone.'}</div>
        <p class="small">Treat the token like a password. The desktop launcher stores it with Windows user encryption and never writes it into the addon or SavedVariables.</p>
        <script>
          function copyField(id) {
            const field = document.getElementById(id);
            field.select();
            document.execCommand('copy');
          }
        </script>
      </body>
    </html>
  `;
}

function doPost(event) {
  try {
    const payload = getAuthenticatedDesktopPayload_(event);

    if (payload.action === 'replaceWoWTsvDump') {
      return jsonResponse_(replaceWowTsvDump_(payload));
    }

    if (payload.action === 'validateRaidPlan') {
      return jsonResponse_(validateRaidPlanPublish_(payload));
    }

    if (payload.action === 'publishRaidPlan') {
      return jsonResponse_(publishRaidPlan_(payload));
    }

    if (payload.action === 'prepareRaidPlan') {
      return jsonResponse_(prepareRaidPlanPublish_(payload));
    }

    if (payload.action === 'completeRaidPlanPublish') {
      return jsonResponse_(completeRaidPlanPublish_(payload));
    }

    throw new Error('Unsupported desktop TSV action.');
  } catch (error) {
    return jsonResponse_({ ok: false, error: String(error && error.message || error) });
  }
}

function getAuthenticatedDesktopPayload_(event) {
  if (!event || !event.postData || !event.postData.contents) {
    throw new Error('Missing JSON request body.');
  }

  const payload = JSON.parse(event.postData.contents);
  const expectedToken = PropertiesService
    .getDocumentProperties()
    .getProperty(DESKTOP_TSV_TOKEN_PROPERTY);

  if (!expectedToken || payload.token !== expectedToken) {
    throw new Error('Desktop TSV authentication failed.');
  }

  return payload;
}

function buildDesktopTsvPlan_(payload) {
  if (!payload || typeof payload.tsv !== 'string') {
    throw new Error('TSV payload is missing.');
  }

  const rows = parseDesktopTsv_(payload.tsv);
  validateDesktopTsv_(rows, payload.tsv);

  const maxColumns = rows.reduce(function(maximum, row) {
    return Math.max(maximum, row.length);
  }, 0);

  if (rows.length > TSV_DUMP_CLEAR_ROWS || maxColumns > TSV_DUMP_CLEAR_COLUMNS) {
    throw new Error('TSV exceeds the managed WoW TSV Dump area.');
  }

  const safeRows = rows.map(function(row) {
    const copy = row.map(function(value) {
      return /^[=+@]/.test(value) ? "'" + value : value;
    });
    while (copy.length < maxColumns) copy.push('');
    return copy;
  });

  return {
    rows: safeRows,
    rowCount: safeRows.length,
    columnCount: maxColumns,
    sourceWrittenAt: payload.sourceWrittenAt || ''
  };
}

function replaceWowTsvDump_(payload) {
  const plan = buildDesktopTsvPlan_(payload);

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) throw new Error('Another TSV sync is already running.');

  try {
    const spreadsheet = getRaidSpreadsheet_();
    const sheet = spreadsheet.getSheetByName(TSV_DUMP_SHEET_NAME);
    if (!sheet) throw new Error('Required sheet not found: ' + TSV_DUMP_SHEET_NAME);

    writeWowTsvDump_(sheet, plan);
    SpreadsheetApp.flush();

    return buildDesktopResponse_(plan, 'replaceWoWTsvDump');
  } finally {
    lock.releaseLock();
  }
}

function writeWowTsvDump_(sheet, plan) {
  // Write the validated replacement first so a transient setValues failure
  // leaves the prior dump intact. Then remove only stale cells to the right
  // and below the newly managed rectangle.
  sheet.getRange(1, 1, plan.rowCount, plan.columnCount).setValues(plan.rows);
  if (plan.columnCount < TSV_DUMP_CLEAR_COLUMNS) {
    sheet.getRange(1, plan.columnCount + 1, TSV_DUMP_CLEAR_ROWS, TSV_DUMP_CLEAR_COLUMNS - plan.columnCount).clearContent();
  }
  if (plan.rowCount < TSV_DUMP_CLEAR_ROWS) {
    sheet.getRange(plan.rowCount + 1, 1, TSV_DUMP_CLEAR_ROWS - plan.rowCount, plan.columnCount).clearContent();
  }
}

function buildDesktopResponse_(plan, action) {
  return {
    ok: true,
    action: action,
    sheet: TSV_DUMP_SHEET_NAME,
    range: 'A1:' + columnName_(plan.columnCount) + plan.rowCount,
    rows: plan.rowCount,
    columns: plan.columnCount,
    sourceWrittenAt: plan.sourceWrittenAt
  };
}

function buildLiveRaidPlanUpdates_(rows) {
  return LIVE_PLAN_BLOCKS.map(function(config) {
    const values = [];

    for (let rowOffset = 0; rowOffset < config.rows; rowOffset++) {
      const source = rows[config.sourceRow - 1 + rowOffset] || [];
      const row = [];

      for (let columnOffset = 0; columnOffset < config.columns; columnOffset++) {
        row.push(source[config.sourceColumn - 1 + columnOffset] || '');
      }

      values.push(row);
    }

    return {
      label: config.label,
      targetSheet: config.targetSheet,
      targetRange: config.targetRange,
      rows: config.rows,
      columns: config.columns,
      values: values
    };
  });
}

function resolveLiveRaidPlanTargets_(spreadsheet, rows) {
  return buildLiveRaidPlanUpdates_(rows).map(function(update) {
    const sheet = spreadsheet.getSheetByName(update.targetSheet);
    if (!sheet) throw new Error('Required sheet not found: ' + update.targetSheet);

    const range = sheet.getRange(update.targetRange);
    if (range.getNumRows() !== update.rows || range.getNumColumns() !== update.columns) {
      throw new Error('Live range size mismatch: ' + update.targetSheet + '!' + update.targetRange);
    }

    update.range = range;
    update.previousValues = range.getValues();
    return update;
  });
}

function describeLiveRaidPlanTargets_(targets) {
  return targets.map(function(target) {
    return target.targetSheet + '!' + target.targetRange;
  });
}

function applyLiveRaidPlan_(targets) {
  try {
    targets.forEach(function(target) {
      target.range.setValues(target.values);
    });
    SpreadsheetApp.flush();
  } catch (error) {
    restoreLiveRaidPlan_(targets);
    throw error;
  }
}

function restoreLiveRaidPlan_(targets) {
  targets.forEach(function(target) {
    target.range.setValues(target.previousValues);
  });
  SpreadsheetApp.flush();
}

function buildPublishFingerprint_(payload) {
  const material =
    'publish-protocol:' +
    RAID_PUBLISH_PROTOCOL_VERSION +
    '\n' +
    String(payload.sourceWrittenAt || '') +
    '\n' +
    String(payload.tsv || '');
  const digest = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    material,
    Utilities.Charset.UTF_8
  );
  return Utilities.base64EncodeWebSafe(digest).replace(/=+$/g, '');
}

function readLastPublishState_(properties) {
  const raw = properties.getProperty(LAST_PUBLISH_STATE_PROPERTY);
  if (!raw) return { raw: '', value: null };

  try {
    return { raw: raw, value: JSON.parse(raw) };
  } catch (error) {
    return { raw: raw, value: null };
  }
}

function restoreLastPublishState_(properties, prior) {
  if (prior.raw) {
    properties.setProperty(LAST_PUBLISH_STATE_PROPERTY, prior.raw);
  } else {
    properties.deleteProperty(LAST_PUBLISH_STATE_PROPERTY);
  }
}

function buildConservativePostedState_(state) {
  return {
    protocol: Number(state.protocol || RAID_PUBLISH_PROTOCOL_VERSION),
    fingerprint: String(state.fingerprint || ''),
    state: 'posted',
    publishedAt: String(state.publishedAt || state.startedAt || new Date().toISOString()),
    sourceWrittenAt: String(state.sourceWrittenAt || ''),
    liveSheets: state.liveSheets || [],
    files: state.files || RAID_EXPORTS.map(function(config) {
      return config.safeName + '.png';
    }),
    imageDetails: state.imageDetails || [],
    discordConfirmation: 'conservative-no-retry'
  };
}

function recoverAmbiguousPublishState_(properties, state) {
  const recovered = buildConservativePostedState_(state);
  properties.setProperty(LAST_PUBLISH_STATE_PROPERTY, JSON.stringify(recovered));
  return recovered;
}

function validateRaidPlanPublish_(payload) {
  const plan = buildDesktopTsvPlan_(payload);
  const spreadsheet = getRaidSpreadsheet_();
  const dumpSheet = spreadsheet.getSheetByName(TSV_DUMP_SHEET_NAME);
  if (!dumpSheet) throw new Error('Required sheet not found: ' + TSV_DUMP_SHEET_NAME);

  const targets = resolveLiveRaidPlanTargets_(spreadsheet, plan.rows);
  getWebhook_();

  const response = buildDesktopResponse_(plan, 'validateRaidPlan');
  response.publishProtocol = RAID_PUBLISH_PROTOCOL_VERSION;
  response.ready = true;
  response.liveSheets = describeLiveRaidPlanTargets_(targets);
  response.imagePlan = getRaidExportManifest_();
  response.discordConfigured = true;
  return response;
}

function buildPublishedDuplicateResponse_(plan, action, state) {
  const response = buildDesktopResponse_(plan, action);
  response.publishProtocol = RAID_PUBLISH_PROTOCOL_VERSION;
  response.alreadyPublished = true;
  response.discordPosted = false;
  response.liveSheets = state.liveSheets || [];
  response.files = state.files || [];
  response.imageDetails = state.imageDetails || [];
  response.publishedAt = state.publishedAt || '';
  return response;
}

function publishRaidPlan_() {
  throw new Error('The legacy 1024px publisher is disabled. Install the current desktop launcher and use the 4K publish workflow.');
}

function prepareRaidPlanPublish_(payload) {
  const plan = buildDesktopTsvPlan_(payload);
  const fingerprint = buildPublishFingerprint_(payload);
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) throw new Error('Another raid-plan publish is already running.');

  let targets = [];
  let livePlanApplied = false;

  try {
    const properties = PropertiesService.getDocumentProperties();
    const priorState = readLastPublishState_(properties);

    if (priorState.value && priorState.value.state === 'posting') {
      priorState.value = recoverAmbiguousPublishState_(properties, priorState.value);
    }

    if (
      priorState.value &&
      priorState.value.fingerprint === fingerprint &&
      priorState.value.state === 'posted'
    ) {
      return buildPublishedDuplicateResponse_(plan, 'prepareRaidPlan', priorState.value);
    }

    const spreadsheet = getRaidSpreadsheet_();
    const dumpSheet = spreadsheet.getSheetByName(TSV_DUMP_SHEET_NAME);
    if (!dumpSheet) throw new Error('Required sheet not found: ' + TSV_DUMP_SHEET_NAME);

    getWebhook_();
    targets = resolveLiveRaidPlanTargets_(spreadsheet, plan.rows);
    writeWowTsvDump_(dumpSheet, plan);
    applyLiveRaidPlan_(targets);
    livePlanApplied = true;

    const pdfs = createRaidPdfPayloads_(spreadsheet);
    const liveSheets = describeLiveRaidPlanTargets_(targets);
    const publishTicket =
      priorState.value &&
      priorState.value.fingerprint === fingerprint &&
      priorState.value.state === 'prepared' &&
      priorState.value.publishTicket
        ? priorState.value.publishTicket
        : Utilities.getUuid();
    const preparedAt = new Date().toISOString();

    properties.setProperty(LAST_PUBLISH_STATE_PROPERTY, JSON.stringify({
      protocol: RAID_PUBLISH_PROTOCOL_VERSION,
      fingerprint: fingerprint,
      publishTicket: publishTicket,
      state: 'prepared',
      preparedAt: preparedAt,
      sourceWrittenAt: plan.sourceWrittenAt,
      liveSheets: liveSheets
    }));

    const response = buildDesktopResponse_(plan, 'prepareRaidPlan');
    response.publishProtocol = RAID_PUBLISH_PROTOCOL_VERSION;
    response.publishTicket = publishTicket;
    response.preparedAt = preparedAt;
    response.alreadyPublished = false;
    response.discordPosted = false;
    response.liveSheets = liveSheets;
    response.pdfs = pdfs;
    return response;
  } catch (error) {
    if (livePlanApplied) restoreLiveRaidPlan_(targets);
    throw error;
  } finally {
    lock.releaseLock();
  }
}

function completeRaidPlanPublish_(payload) {
  if (Number(payload.publishProtocol) !== RAID_PUBLISH_PROTOCOL_VERSION) {
    throw new Error('Desktop publisher protocol mismatch. Update the desktop launcher before publishing.');
  }

  const plan = buildDesktopTsvPlan_(payload);
  const fingerprint = buildPublishFingerprint_(payload);
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) throw new Error('Another raid-plan publish is already running.');

  try {
    const properties = PropertiesService.getDocumentProperties();
    const priorState = readLastPublishState_(properties);
    const state = priorState.value;

    if (state && state.fingerprint === fingerprint && state.state === 'posted') {
      return buildPublishedDuplicateResponse_(plan, 'completeRaidPlanPublish', state);
    }

    if (state && state.state === 'posting') {
      if (state.fingerprint === fingerprint) {
        return buildPublishedDuplicateResponse_(
          plan,
          'completeRaidPlanPublish',
          recoverAmbiguousPublishState_(properties, state)
        );
      }
      throw new Error('A different raid plan already reached the Discord posting step. Run the desktop icon again so it can be finalized without a duplicate post.');
    }

    if (
      !state ||
      state.state !== 'prepared' ||
      state.fingerprint !== fingerprint ||
      !payload.publishTicket ||
      payload.publishTicket !== state.publishTicket
    ) {
      throw new Error('The 4K publish ticket is missing, expired, or does not match this raid plan. Run the desktop icon again.');
    }

    const webhook = getWebhook_();
    const pngs = validateRaidPngUploads_(payload.images);
    const startedAt = new Date().toISOString();

    properties.setProperty(LAST_PUBLISH_STATE_PROPERTY, JSON.stringify({
      protocol: RAID_PUBLISH_PROTOCOL_VERSION,
      fingerprint: fingerprint,
      publishTicket: state.publishTicket,
      state: 'posting',
      startedAt: startedAt,
      sourceWrittenAt: plan.sourceWrittenAt,
      liveSheets: state.liveSheets || []
    }));

    let result;
    try {
      result = sendDiscordWebhookFiles_(
        webhook,
        'Raid positions: BPC & BQL',
        pngs
      );
    } catch (error) {
      throw new Error(
        'Discord did not return a confirmed success. Automatic retry is blocked to prevent a duplicate post: ' +
        String(error && error.message || error)
      );
    }

    if (result.rateLimited) {
      restoreLastPublishState_(properties, priorState);
      throw new Error('Discord rate limited the webhook before accepting the 4K files. Wait a minute and run the desktop icon again.');
    }

    const publishedAt = new Date().toISOString();
    const files = pngs.map(function(blob) { return blob.getName(); });
    const imageDetails = result.attachments || [];
    properties.setProperty(LAST_PUBLISH_STATE_PROPERTY, JSON.stringify({
      protocol: RAID_PUBLISH_PROTOCOL_VERSION,
      fingerprint: fingerprint,
      state: 'posted',
      publishedAt: publishedAt,
      sourceWrittenAt: plan.sourceWrittenAt,
      liveSheets: state.liveSheets || [],
      files: files,
      imageDetails: imageDetails,
      discordConfirmation: result.confirmation || 'discord-http-2xx',
      discordMessageId: result.messageId || ''
    }));

    const response = buildDesktopResponse_(plan, 'completeRaidPlanPublish');
    response.publishProtocol = RAID_PUBLISH_PROTOCOL_VERSION;
    response.alreadyPublished = false;
    response.discordPosted = true;
    response.liveSheets = state.liveSheets || [];
    response.files = files;
    response.imageDetails = imageDetails;
    response.discordConfirmation = result.confirmation || 'discord-http-2xx';
    response.discordMessageId = result.messageId || '';
    response.publishedAt = publishedAt;
    return response;
  } finally {
    lock.releaseLock();
  }
}

function parseDesktopTsv_(value) {
  if (typeof value !== 'string' || !value.trim()) throw new Error('TSV payload is empty.');
  const lines = value.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  while (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines.map(function(line) { return line.split('\t'); });
}

function validateDesktopTsv_(rows, rawTsv) {
  if (!rows[0] || rows[0][0] !== 'H1') throw new Error('BPC must begin at WoW TSV Dump A1.');
  if (rows.length < 79) throw new Error('Combined BPC/BQL TSV is incomplete.');
  if (!rows[54] || rawTsv.indexOf('COPY A55:Q62') < 0) throw new Error('BQL must begin at WoW TSV Dump row 55.');
  if (!rows[63] || rows[63][0] !== 'H1') throw new Error('BQL group block is not anchored at row 64.');
  if (!rows[75] || rows[75][0] !== '1st') throw new Error('BQL cooldown block is not anchored at row 76.');
}

function columnName_(columnNumber) {
  let name = '';
  for (let value = columnNumber; value > 0; value = Math.floor((value - 1) / 26)) {
    name = String.fromCharCode(65 + ((value - 1) % 26)) + name;
  }
  return name;
}

function jsonResponse_(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function setDiscordWebhook() {
  const ui = SpreadsheetApp.getUi();
  const response = ui.prompt(
    'Discord webhook URL',
    'Paste the webhook URL for #raid-positions.',
    ui.ButtonSet.OK_CANCEL
  );

  if (response.getSelectedButton() !== ui.Button.OK) return;

  const webhook = response.getResponseText().trim();

  if (!/^https:\/\/discord(?:app)?\.com\/api\/webhooks\//.test(webhook)) {
    ui.alert('That does not look like a Discord webhook URL.');
    return;
  }

  rememberBoundSpreadsheet_();
  PropertiesService.getDocumentProperties().setProperty(DISCORD_WEBHOOK_PROPERTY, webhook);
  SpreadsheetApp.getActive().toast('Discord webhook saved.');
}

function previewRaidPngs() {
  const lock = LockService.getDocumentLock();

  if (!lock.tryLock(1000)) {
    throw new Error('Another export is already running. Wait for it to finish.');
  }

  try {
    const ss = SpreadsheetApp.getActive();
    const pngs = createRaidPngs_(ss);

    showPngPreview_(
      pngs,
      'Layout preview only. The desktop icon creates the native 4K files used for Discord.',
      'Raid layout preview'
    );
  } finally {
    lock.releaseLock();
  }
}

function postRaidPngsToDiscord() {
  SpreadsheetApp.getUi().alert(
    'Use the Pizza Warriors Publish Raid Positions desktop icon. It renders the vector sheets as native 4096px PNGs before posting; Apps Script previews are intentionally not sent because Drive limits them to 1024px.'
  );
}

function expectedRaidPngHeight_(config, width) {
  return Math.round(
    width *
    (RAID_PDF_PAGE_HEIGHT_POINTS - config.cropBottomPoints) /
    RAID_PDF_PAGE_WIDTH_POINTS
  );
}

function getRaidExportManifest_() {
  return RAID_EXPORTS.map(function(config) {
    return {
      label: config.label,
      safeName: config.safeName,
      rangeA1: config.rangeA1,
      targetWidth: config.targetWidth,
      expectedHeight: expectedRaidPngHeight_(config, config.targetWidth)
    };
  });
}

function createRaidCroppedPdfs_(ss) {
  return RAID_EXPORTS.map(function(config) {
    const sheet = ss.getSheetByName(config.sheetName);

    if (!sheet) {
      throw new Error('Required sheet not found: ' + config.sheetName);
    }

    ss.toast('Creating ' + config.label + ' PNG...');

    const sourcePdf = exportRangeAsPdf_(ss, sheet, config.rangeA1)
      .setName(config.safeName + '_source.pdf');
    const croppedPdf = cropPdfPage_(sourcePdf, config.cropBottomPoints)
      .setName(config.safeName + '_cropped.pdf');

    return { config: config, blob: croppedPdf };
  });
}

function createRaidPdfPayloads_(ss) {
  return createRaidCroppedPdfs_(ss).map(function(item) {
    return {
      label: item.config.label,
      safeName: item.config.safeName,
      fileName: item.config.safeName + '.pdf',
      targetWidth: item.config.targetWidth,
      expectedHeight: expectedRaidPngHeight_(item.config, item.config.targetWidth),
      base64: Utilities.base64Encode(item.blob.getBytes())
    };
  });
}

function createRaidPngs_(ss) {
  return createRaidCroppedPdfs_(ss).map(function(item) {
    return makePngThumbnail_(item.blob, item.config.safeName);
  });
}

function unsignedByte_(value) {
  return value < 0 ? value + 256 : value;
}

function readPngDimensionsFromBytes_(bytes) {
  if (!bytes || bytes.length < 24) throw new Error('PNG is truncated.');

  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let index = 0; index < signature.length; index++) {
    if (unsignedByte_(bytes[index]) !== signature[index]) {
      throw new Error('Uploaded raid image is not a PNG.');
    }
  }

  function readUint32(offset) {
    return (
      unsignedByte_(bytes[offset]) * 16777216 +
      unsignedByte_(bytes[offset + 1]) * 65536 +
      unsignedByte_(bytes[offset + 2]) * 256 +
      unsignedByte_(bytes[offset + 3])
    );
  }

  const width = readUint32(16);
  const height = readUint32(20);
  if (!width || !height) throw new Error('PNG dimensions are invalid.');
  return { width: width, height: height };
}

function validateRaidPngUploads_(images) {
  if (!Array.isArray(images) || images.length !== RAID_EXPORTS.length) {
    throw new Error('Exactly two 4K raid PNGs are required.');
  }

  const configs = {};
  RAID_EXPORTS.forEach(function(config) { configs[config.safeName] = config; });
  const seen = {};
  const maxBase64Length = Math.ceil(RAID_PNG_MAX_BYTES / 3) * 4 + 4;

  return images.map(function(image) {
    const safeName = image && String(image.safeName || '');
    const config = configs[safeName];
    if (!config || seen[safeName]) throw new Error('Unexpected or duplicate raid image: ' + safeName);
    seen[safeName] = true;

    const encoded = String(image.base64 || '');
    if (
      !encoded ||
      encoded.length > maxBase64Length ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)
    ) {
      throw new Error('Invalid or oversized Base64 PNG for ' + config.label + '.');
    }

    const bytes = Utilities.base64Decode(encoded);
    if (bytes.length > RAID_PNG_MAX_BYTES) {
      throw new Error(config.label + ' exceeds Discord\'s 10 MiB attachment limit.');
    }

    const dimensions = readPngDimensionsFromBytes_(bytes);
    const expectedHeight = expectedRaidPngHeight_(config, config.targetWidth);
    if (
      dimensions.width !== config.targetWidth ||
      Math.abs(dimensions.height - expectedHeight) > 2
    ) {
      throw new Error(
        config.label +
        ' must be a native ' +
        config.targetWidth +
        'px render (received ' +
        dimensions.width +
        'x' +
        dimensions.height +
        ').'
      );
    }

    return Utilities
      .newBlob(bytes, 'image/png', config.safeName + '.png');
  });
}

function getWebhook_() {
  const webhook = PropertiesService
    .getDocumentProperties()
    .getProperty(DISCORD_WEBHOOK_PROPERTY);

  if (webhook) return webhook;

  throw new Error('No Discord webhook configured. Use Raid Positions > Set Discord webhook.');
}

function exportRangeAsPdf_(ss, sheet, rangeA1) {
  const params = {
    format: 'pdf',
    gid: sheet.getSheetId(),
    range: rangeA1,
    portrait: 'false',
    size: '7',
    fitw: 'true',
    sheetnames: 'false',
    printtitle: 'false',
    pagenumbers: 'false',
    gridlines: 'false',
    fzr: 'false',
    top_margin: '0.02',
    bottom_margin: '0.02',
    left_margin: '0.02',
    right_margin: '0.02'
  };

  const query = Object.keys(params)
    .map(function(key) {
      return encodeURIComponent(key) + '=' + encodeURIComponent(params[key]);
    })
    .join('&');

  const url = 'https://docs.google.com/spreadsheets/d/' + ss.getId() + '/export?' + query;

  const response = UrlFetchApp.fetch(url, {
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    muteHttpExceptions: true
  });

  const code = response.getResponseCode();
  const body = response.getContentText();

  if (code < 200 || code >= 300) {
    throw new Error('Sheet export failed with HTTP ' + code + ': ' + body);
  }

  return response.getBlob();
}

function cropPdfPage_(pdfBlob, cropBottomPoints) {
  const bytes = pdfBlob.getBytes();
  const marker = asciiBytes_('/MediaBox');
  const markerIndex = findByteSequence_(bytes, marker, 0);

  if (markerIndex < 0) {
    throw new Error('Cannot crop the PDF: MediaBox was not found.');
  }

  const boxStart = findByte_(bytes, 91, markerIndex, markerIndex + 100);
  const boxEnd = findByte_(bytes, 93, boxStart + 1, boxStart + 100);

  if (boxStart < 0 || boxEnd < 0) {
    throw new Error('Cannot crop the PDF: MediaBox coordinates were not found.');
  }

  const original = bytesToAscii_(bytes, boxStart, boxEnd + 1);
  const values = original.match(/-?\d+(?:\.\d+)?/g);

  if (!values || values.length !== 4) {
    throw new Error('Cannot crop the PDF: unexpected MediaBox ' + original);
  }

  const lowerLeftX = Number(values[0]);
  const lowerLeftY = Number(values[1]);
  const upperRightX = Number(values[2]);
  const upperRightY = Number(values[3]);

  if (
    !Number.isFinite(cropBottomPoints) ||
    cropBottomPoints <= lowerLeftY ||
    cropBottomPoints >= upperRightY
  ) {
    throw new Error('Cannot crop the PDF: invalid lower crop boundary.');
  }

  const compact =
    '[' +
    lowerLeftX + ' ' +
    cropBottomPoints + ' ' +
    upperRightX + ' ' +
    upperRightY +
    ']';

  if (compact.length > original.length) {
    throw new Error('Cannot crop the PDF without rebuilding its cross-reference table.');
  }

  const replacement =
    compact.slice(0, -1) +
    ' '.repeat(original.length - compact.length) +
    ']';

  for (let i = 0; i < replacement.length; i++) {
    bytes[boxStart + i] = replacement.charCodeAt(i);
  }

  return Utilities.newBlob(bytes, 'application/pdf', pdfBlob.getName());
}

function asciiBytes_(value) {
  const bytes = [];

  for (let i = 0; i < value.length; i++) {
    bytes.push(value.charCodeAt(i));
  }

  return bytes;
}

function findByteSequence_(bytes, needle, startIndex) {
  const lastStart = bytes.length - needle.length;

  for (let i = startIndex; i <= lastStart; i++) {
    let matches = true;

    for (let j = 0; j < needle.length; j++) {
      if (bytes[i + j] !== needle[j]) {
        matches = false;
        break;
      }
    }

    if (matches) return i;
  }

  return -1;
}

function findByte_(bytes, target, startIndex, endIndex) {
  const limit = Math.min(endIndex, bytes.length);

  for (let i = Math.max(0, startIndex); i < limit; i++) {
    if (bytes[i] === target) return i;
  }

  return -1;
}

function bytesToAscii_(bytes, startIndex, endIndex) {
  let value = '';

  for (let i = startIndex; i < endIndex; i++) {
    const byte = bytes[i] < 0 ? bytes[i] + 256 : bytes[i];
    value += String.fromCharCode(byte);
  }

  return value;
}

function makePngThumbnail_(pdfBlob, safeName) {
  const temp = DriveApp.createFile(pdfBlob).setName(safeName + '_source.pdf');

  try {
    const fileId = temp.getId();
    const token = ScriptApp.getOAuthToken();

    for (let i = 0; i < 45; i++) {
      Utilities.sleep(1000);

      const url =
        'https://drive.google.com/thumbnail?id=' +
        encodeURIComponent(fileId) +
        '&sz=w3000';

      const response = UrlFetchApp.fetch(url, {
        headers: { Authorization: 'Bearer ' + token },
        muteHttpExceptions: true,
        followRedirects: true
      });

      const code = response.getResponseCode();
      const headers = response.getHeaders();
      const contentType = headers['Content-Type'] || headers['content-type'] || '';

      if (code >= 200 && code < 300 && contentType.indexOf('image/') === 0) {
        return response.getBlob().getAs(MimeType.PNG).setName(safeName + '.png');
      }
    }

    throw new Error('Google Drive did not create an image preview. Try again in a minute.');
  } finally {
    temp.setTrashed(true);
  }
}

function sendDiscordWebhookFiles_(webhook, content, fileBlobs) {
  const attachments = [];
  const embeds = [];
  const payload = { payload_json: '' };

  fileBlobs.forEach(function(blob, index) {
    attachments.push({ id: index, filename: blob.getName() });
    embeds.push({ image: { url: 'attachment://' + blob.getName() } });
    payload['files[' + index + ']'] = blob;
  });

  payload.payload_json = JSON.stringify({
    content: content,
    attachments: attachments,
    embeds: embeds
  });

  const waitUrl = webhook + (webhook.indexOf('?') >= 0 ? '&' : '?') + 'wait=true';
  const response = UrlFetchApp.fetch(waitUrl, {
    method: 'post',
    muteHttpExceptions: true,
    payload: payload
  });

  const code = response.getResponseCode();
  const body = response.getContentText();

  if (code === 429) {
    return {
      rateLimited: true,
      message: 'Discord is rate limiting this webhook. Copy or download these PNGs and paste them into Discord manually.'
    };
  }

  if (code < 200 || code >= 300) {
    throw new Error('Discord webhook failed with HTTP ' + code + ': ' + body);
  }

  let message = null;
  try {
    if (body) message = JSON.parse(body);
  } catch (error) {
    message = null;
  }

  const verification = buildDiscordAttachmentDetails_(message, fileBlobs);
  return {
    rateLimited: false,
    attachments: verification.attachments,
    confirmation: verification.confirmation,
    messageId: message && message.id ? String(message.id) : ''
  };
}

function buildDiscordAttachmentDetails_(message, fileBlobs) {
  const returned = message && Array.isArray(message.attachments) ? message.attachments : [];
  let matchedCount = 0;

  const details = fileBlobs.map(function(blob) {
    const name = blob.getName();
    const bytes = blob.getBytes();
    const localDimensions = readPngDimensionsFromBytes_(bytes);
    const attachment = returned.filter(function(value) {
      return value && value.filename === name;
    })[0];

    if (attachment && Number(attachment.width) > 0 && Number(attachment.height) > 0) {
      matchedCount++;
      return {
        filename: name,
        width: Number(attachment.width),
        height: Number(attachment.height),
        size: Number(attachment.size || bytes.length),
        confirmedBy: 'discord-attachment'
      };
    }

    return {
      filename: name,
      width: localDimensions.width,
      height: localDimensions.height,
      size: bytes.length,
      confirmedBy: 'validated-upload'
    };
  });

  return {
    attachments: details,
    confirmation: matchedCount === fileBlobs.length
      ? 'discord-attachments'
      : 'discord-http-2xx'
  };
}

function showPngPreview_(pngBlobs, message, dialogTitle) {
  const images = pngBlobs.map(function(blob, index) {
    return {
      id: 'img' + index,
      name: blob.getName(),
      base64: Utilities.base64Encode(blob.getBytes())
    };
  });

  const html = HtmlService.createHtmlOutput(buildPreviewHtml_(images, message))
    .setWidth(1100)
    .setHeight(800);

  SpreadsheetApp.getUi().showModalDialog(html, dialogTitle);
}

function buildPreviewHtml_(images, message) {
  const imageCards = images.map(function(image) {
    return `
      <section class="card">
        <h3>${escapeHtml_(image.name)}</h3>
        <div class="actions">
          <button onclick="copyImage('${image.id}')">Copy image</button>
          <a download="${escapeHtml_(image.name)}" href="data:image/png;base64,${image.base64}">
            Download PNG
          </a>
        </div>
        <img id="${image.id}" src="data:image/png;base64,${image.base64}">
      </section>
    `;
  }).join('');

  return `
    <!doctype html>
    <html>
      <head>
        <style>
          body {
            font-family: Arial, sans-serif;
            margin: 18px;
            color: #111827;
          }
          .message {
            margin-bottom: 14px;
            font-size: 14px;
            font-weight: 700;
          }
          .hint {
            margin-bottom: 16px;
            font-size: 13px;
            color: #374151;
          }
          .grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 16px;
          }
          .card {
            border: 1px solid #d1d5db;
            padding: 12px;
          }
          h3 {
            margin: 0 0 10px;
            font-size: 15px;
          }
          .actions {
            margin-bottom: 10px;
          }
          button {
            background: #1f4e79;
            color: white;
            border: 0;
            border-radius: 4px;
            padding: 9px 12px;
            font-weight: 700;
            cursor: pointer;
            margin-right: 10px;
          }
          a {
            color: #1f4e79;
            font-weight: 700;
          }
          img {
            display: block;
            width: 100%;
            border: 1px solid #e5e7eb;
          }
          #status {
            margin: 10px 0 14px;
            font-weight: 700;
          }
        </style>
      </head>
      <body>
        <div class="message">${escapeHtml_(message)}</div>
        <div class="hint">Click Copy image, then paste into Discord. If Chrome blocks clipboard access here, use Download PNG.</div>
        <div id="status"></div>
        <div class="grid">${imageCards}</div>

        <script>
          async function copyImage(id) {
            const status = document.getElementById('status');

            try {
              if (!navigator.clipboard || !window.ClipboardItem) {
                status.textContent = 'Clipboard copy is not available here. Use Download PNG instead.';
                return;
              }

              const img = document.getElementById(id);
              const blob = await fetch(img.src).then(function(response) {
                return response.blob();
              });

              await navigator.clipboard.write([
                new ClipboardItem({ [blob.type]: blob })
              ]);

              status.textContent = 'Copied ' + id + '. Paste it into Discord.';
            } catch (err) {
              status.textContent = 'Copy failed. Use Download PNG instead.';
            }
          }
        </script>
      </body>
    </html>
  `;
}

function escapeHtml_(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
