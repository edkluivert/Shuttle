/// The page a browser gets when it opens this device's address.
///
/// This is what makes the other end work without installing anything: one
/// device runs the server, you type its address into a browser, and you can
/// pull files off it or drop files onto it.
///
/// The first version of this page never said *whose* files these were or
/// which way anything was moving — it just listed files under "Files shared
/// with you" and had a drop zone below. Opened on a phone, pointed at a Mac,
/// there was no way to tell what you were looking at or where an uploaded
/// file had gone. Every section now names both ends and shows its direction.
String buildWebPage(
  String rawDeviceName, {
  bool viewedFromSelf = false,
  List<String> addresses = const [],
  int? port,
}) {
  if (viewedFromSelf) {
    return _selfPage(rawDeviceName, addresses, port);
  }
  return _transferPage(rawDeviceName);
}

/// What the serving device's own browser gets.
///
/// There is nothing useful this page can do here — it would be offering to
/// copy this machine's files onto itself — so instead of a broken-looking
/// transfer UI it shows the one thing that is actually needed: the address,
/// large, ready to type on the other device.
String _selfPage(String rawDeviceName, List<String> addresses, int? port) {
  final deviceName = _htmlEscape(rawDeviceName);
  final urls = port == null
      ? const <String>[]
      : addresses.map((a) => 'http://$a:$port').toList();

  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$deviceName — Shuttle</title>
<style>
${_sharedCss()}
  .big { font-size: clamp(20px, 6vw, 30px); font-weight: 700; letter-spacing: -0.5px;
         background: linear-gradient(135deg, var(--accent), var(--mint));
         -webkit-background-clip: text; background-clip: text; color: transparent;
         font-variant-numeric: tabular-nums; word-break: break-all; }
  .step { display: flex; gap: 13px; align-items: flex-start; margin-bottom: 18px; }
  .num { width: 24px; height: 24px; border-radius: 50%; flex: none; font-size: 12px;
         font-weight: 700; display: grid; place-items: center;
         background: var(--accent-soft); color: var(--accent); }
  .copy { margin-top: 14px; padding: 10px 16px; border-radius: 10px; border: 1px solid var(--line);
          background: var(--card2); color: var(--text); font: inherit; font-size: 13.5px;
          font-weight: 600; cursor: pointer; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="mark">⇅</div>
    <div>
      <h1>$deviceName</h1>
      <p class="sub">Shuttle</p>
    </div>
  </header>

  <div class="link" style="border-color: var(--accent);">
    <span>👋 You are viewing this <b>on $deviceName itself</b>, so there is
    nothing to transfer — this page is meant for your <b>other</b> device.</span>
  </div>

  <h2>What to do</h2>
  <div class="card" style="padding: 20px 18px;">
    <div class="step">
      <span class="num">1</span>
      <div>On your phone or another computer, open a browser and type this
      address:</div>
    </div>
    ${urls.isEmpty ? '<p class="empty">Waiting for a network connection…</p>' : '''
    <div style="margin: 0 0 6px 37px;">
      <div class="big" id="url">${_htmlEscape(urls.first)}</div>
      <button class="copy" onclick="copyUrl()">Copy address</button>
    </div>
    ${urls.length > 1 ? '''
    <p style="margin: 16px 0 4px 37px; color: var(--muted); font-size: 13px;">
      Other networks this device is on:</p>
    <div style="margin-left: 37px; color: var(--muted); font-size: 13.5px;">
      ${urls.skip(1).map((u) => '<div>${_htmlEscape(u)}</div>').join()}
    </div>''' : ''}
    '''}
    <div class="step" style="margin-top: 22px;">
      <span class="num">2</span>
      <div>That device can then pull whatever $deviceName is sharing, and
      drop files back onto it.</div>
    </div>
    <div class="step" style="margin-bottom: 0;">
      <span class="num">3</span>
      <div>Both devices must be on the same Wi-Fi.</div>
    </div>
  </div>
</div>
<script>
function copyUrl() {
  const text = document.getElementById('url').textContent.trim();
  navigator.clipboard.writeText(text).then(() => {
    const b = document.querySelector('.copy');
    b.textContent = 'Copied';
    setTimeout(() => b.textContent = 'Copy address', 1600);
  });
}
</script>
</body>
</html>
''';
}

String _transferPage(String rawDeviceName) {
  // The name is whatever the user typed into the rename box. It lands in both
  // markup and a script literal here, so it is escaped for each — a device
  // called `<b>Mac</b>` should read as that, not render as bold, and one
  // called `O'Brien's Mac` must not end the JavaScript string.
  final deviceName = _htmlEscape(rawDeviceName);

  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$deviceName — Shuttle</title>
<style>
${_sharedCss()}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="mark">⇅</div>
    <div>
      <h1>$deviceName</h1>
      <p class="sub">Shuttle</p>
    </div>
  </header>

  <div class="link">
    <span class="dot"></span>
    <span>You are connected to <b>$deviceName</b> over your local network.
    Nothing here leaves it.</span>
  </div>

  <h2><span class="arrow">↓</span> Download from $deviceName</h2>
  <div class="card" id="files"><div class="empty">Loading…</div></div>

  <h2><span class="arrow">↑</span> Send to $deviceName</h2>
  <div id="drop">
    <p style="margin:0"><b>Choose files</b> or drag them here</p>
    <progress id="bar" value="0" max="100" hidden></progress>
    <div class="status" id="status"></div>
  </div>
  <div class="card" id="sent" hidden></div>
  <input type="file" id="picker" multiple>
</div>

<script>
const DEVICE = ${_jsString(rawDeviceName)};
const filesEl = document.getElementById('files');
const sentEl = document.getElementById('sent');
const drop = document.getElementById('drop');
const picker = document.getElementById('picker');
const bar = document.getElementById('bar');
const status = document.getElementById('status');

function human(n) {
  if (n < 1024) return n + ' B';
  const u = ['KB','MB','GB','TB'];
  let v = n / 1024, i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (v < 10 ? v.toFixed(1) : Math.round(v)) + ' ' + u[i];
}

async function loadFiles() {
  try {
    const res = await fetch('/api/files');
    const list = await res.json();
    if (!list.length) {
      // Saying only "nothing here" left people looking for a file browser
      // that does not exist. Nothing is listed until someone puts it in the
      // share list on the other device, and that is the missing step worth
      // naming.
      filesEl.innerHTML =
        '<div class="empty"><b>Nothing shared yet.</b><br>' +
        'Open Shuttle on ' + DEVICE + ' and tap ' +
        '<b>Add files</b> — whatever you add appears here.<br>' +
        '<span class="hint">Only files added there are visible. ' +
        'The rest of ' + DEVICE + ' stays private.</span></div>';
      return;
    }
    filesEl.innerHTML = list.map((f, i) =>
      '<a class="row" href="/download/' + i + '" download>' +
        '<span class="ico">↓</span>' +
        '<span class="name"></span>' +
        '<span class="size">' + human(f.size) + '</span>' +
      '</a>'
    ).join('');
    // Names are set as text, never as markup — a file called
    // `<img onerror=...>` would otherwise run in whoever opened this page.
    filesEl.querySelectorAll('.name').forEach((el, i) => el.textContent = list[i].name);
  } catch (e) {
    filesEl.innerHTML = '<div class="empty">Could not reach ' + DEVICE + '.</div>';
  }
}

/// Confirms where each file actually went. "1 file sent" left people
/// wondering whether anything had happened at all.
function recordSent(file) {
  sentEl.hidden = false;
  const row = document.createElement('div');
  row.className = 'row';

  const ico = document.createElement('span');
  ico.className = 'ico in';
  ico.textContent = '✓';

  const name = document.createElement('span');
  name.className = 'name';
  name.textContent = file.name + ' → ' + DEVICE;

  const size = document.createElement('span');
  size.className = 'size';
  size.textContent = human(file.size);

  row.append(ico, name, size);
  sentEl.prepend(row);
}

function upload(files) {
  if (!files.length) return;
  let done = 0;

  const next = () => {
    if (done >= files.length) {
      status.textContent = 'Saved on ' + DEVICE;
      bar.hidden = true;
      return;
    }
    const file = files[done];
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', '/upload?name=' + encodeURIComponent(file.name));
    bar.hidden = false;
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        bar.value = (e.loaded / e.total) * 100;
        status.textContent = 'Sending ' + file.name + ' — ' +
          human(e.loaded) + ' of ' + human(e.total);
      }
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        recordSent(file);
        done++;
        next();
      } else {
        status.textContent = 'Failed: ' + file.name;
        bar.hidden = true;
      }
    };
    xhr.onerror = () => {
      status.textContent = 'Failed: ' + file.name;
      bar.hidden = true;
    };
    status.textContent = 'Sending ' + file.name + '…';
    xhr.send(file);
  };
  next();
}

drop.addEventListener('click', () => picker.click());
picker.addEventListener('change', () => upload([...picker.files]));
['dragenter','dragover'].forEach(t => drop.addEventListener(t, e => {
  e.preventDefault(); drop.classList.add('over');
}));
['dragleave','drop'].forEach(t => drop.addEventListener(t, e => {
  e.preventDefault(); drop.classList.remove('over');
}));
drop.addEventListener('drop', e => upload([...e.dataTransfer.files]));

loadFiles();
setInterval(loadFiles, 4000);
</script>
</body>
</html>
''';
}

String _htmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The device name reaches JavaScript as data, not as source.
String _jsString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', ' ')
      // `</script>` inside a string literal still closes the block in HTML
      // parsing, so the angle bracket goes out as an escape.
      .replaceAll('<', r'\x3C');
  return "'$escaped'";
}

/// One stylesheet for both pages, so the "wrong device" screen cannot drift
/// away from the transfer screen it sits beside.
String _sharedCss() => '''
  :root {
    color-scheme: light dark;
    --bg: #F7F8FC; --card: #FFFFFF; --card2: #F1F3F9;
    --text: #0D1017; --muted: #636D82; --line: #E4E7F0;
    --accent: #6344F5; --accent-soft: #EDE9FF;
    --mint: #0FA97F; --mint-soft: #E0F7F0;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0B0C11; --card: #13151C; --card2: #191C25;
      --text: #F3F5F9; --muted: #8E97AB; --line: #242833;
      --accent: #7C5CFF; --accent-soft: #1D1A33;
      --mint: #2DD4A7; --mint-soft: #10281F;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 28px 20px 72px; background: var(--bg); color: var(--text);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .wrap { max-width: 660px; margin: 0 auto; }

  header { display: flex; align-items: center; gap: 13px; margin-bottom: 8px; }
  .mark {
    width: 38px; height: 38px; border-radius: 10px; flex: none;
    background: linear-gradient(135deg, var(--accent), var(--mint));
    display: grid; place-items: center; color: #fff; font-size: 19px;
  }
  h1 { font-size: 19px; margin: 0; letter-spacing: -0.3px; }
  .sub { color: var(--muted); font-size: 13px; margin: 1px 0 0; }

  .link {
    display: flex; align-items: center; gap: 10px; margin: 22px 0 30px;
    padding: 13px 16px; border: 1px solid var(--line); border-radius: 14px;
    background: var(--card); font-size: 13.5px; color: var(--muted);
  }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--mint); flex: none;
         box-shadow: 0 0 0 3px color-mix(in srgb, var(--mint) 22%, transparent); }
  .link b { color: var(--text); font-weight: 600; }

  h2 { font-size: 11px; text-transform: uppercase; letter-spacing: .8px;
       color: var(--muted); margin: 0 0 10px 2px; font-weight: 600; }
  .arrow { color: var(--accent); }

  .card { background: var(--card); border: 1px solid var(--line);
          border-radius: 16px; overflow: hidden; margin-bottom: 30px; }
  .row { display: flex; align-items: center; gap: 13px; padding: 13px 16px;
         text-decoration: none; color: inherit; }
  .row + .row { border-top: 1px solid var(--line); }
  .row:hover { background: var(--card2); }
  .ico { width: 34px; height: 34px; border-radius: 9px; flex: none;
         display: grid; place-items: center; font-size: 15px;
         background: var(--accent-soft); color: var(--accent); }
  .ico.in { background: var(--mint-soft); color: var(--mint); }
  .name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .size { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; flex: none; }
  .empty { padding: 26px 20px; text-align: center; color: var(--muted);
           font-size: 14px; line-height: 1.65; }
  .empty b { color: var(--text); }
  .hint { display: inline-block; margin-top: 10px; font-size: 12.5px; opacity: .75; }

  #drop { border: 1.5px dashed var(--line); border-radius: 16px; padding: 32px 20px;
          text-align: center; color: var(--muted); cursor: pointer;
          transition: border-color .15s, background .15s; background: var(--card); }
  #drop.over { border-color: var(--accent); background: var(--accent-soft); color: var(--text); }
  #drop b { color: var(--accent); }
  progress { width: 100%; height: 5px; margin-top: 16px; border-radius: 4px; }
  .status { margin-top: 10px; font-size: 13px; }
  input[type=file] { display: none; }
''';
