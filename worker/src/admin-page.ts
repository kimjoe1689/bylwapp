// Inlined so `wrangler deploy` uploads a single ES module. The page is the Go
// admin UI plus a 6-digit pairing code for collectors that would otherwise
// paste a device token by hand.

export const ADMIN_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>bylwapp 管理后台</title>
  <style>
    :root { --ink:#1c1915; --muted:#5e584e; --line:#e4dfd4; --paper:#f6f3ec; --card:#fffdf8; --accent:#0f6e56; }
    * { box-sizing: border-box; }
    body { margin:0; font:15px/1.5 "Source Han Sans SC","Noto Sans SC","PingFang SC","Microsoft YaHei",sans-serif; color:var(--ink); background:var(--paper); }
    header, main { width:min(1100px, calc(100% - 28px)); margin:0 auto; }
    header { padding:24px 0 8px; display:flex; justify-content:space-between; gap:12px; align-items:end; }
    h1 { margin:0; font-size:28px; }
    h2 { margin:0 0 10px; font-size:18px; }
    .note { color:var(--muted); margin:6px 0 0; }
    section { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; margin:14px 0; }
    label { display:flex; flex-direction:column; gap:4px; font-size:13px; color:var(--muted); }
    input, select, button { font:inherit; border:1px solid var(--line); border-radius:10px; padding:8px 10px; background:white; color:var(--ink); }
    button { background:var(--accent); color:white; border-color:var(--accent); cursor:pointer; }
    button.ghost { background:white; color:var(--ink); }
    .row { display:flex; flex-wrap:wrap; gap:10px; align-items:end; }
    table { width:100%; border-collapse:collapse; }
    th, td { text-align:left; padding:7px 6px; border-bottom:1px solid var(--line); vertical-align:top; font-size:13px; }
    .cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:10px; }
    .card { border:1px solid var(--line); border-radius:12px; padding:12px; }
    .stale { color:#8d2f2f; }
    .banner { display:none; margin-top:10px; padding:10px; border-radius:10px; background:#f8e8e4; color:#8d2f2f; }
    svg { width:100%; height:180px; background:#fbfaf6; border-radius:12px; }
    code { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:12px; }
    .code { font:700 40px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; letter-spacing:0.3em; margin:8px 0 0; }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>bylwapp 管理后台</h1>
      <p class="note">采集端是手机应用。这里只显示服务器已经收到的副本，最近 100 条不是丢失清单，也不能当作论文结果。</p>
    </div>
    <button class="ghost" id="logout" type="button" hidden>退出</button>
  </header>
  <main>
    <div id="banner" class="banner"></div>
    <section id="login">
      <h2>护理者 / 管理员登录</h2>
      <form id="login-form" class="row">
        <label>用户名<input name="username" required autocomplete="username"></label>
        <label>密码<input name="password" type="password" required autocomplete="current-password"></label>
        <button type="submit">登录</button>
      </form>
    </section>
    <div id="app" hidden>
      <section>
        <div class="row" style="justify-content:space-between">
          <h2>采集端状态</h2>
          <button class="ghost" id="refresh" type="button">刷新</button>
        </div>
        <div id="devices" class="cards"></div>
      </section>
      <section>
        <div class="row">
          <h2 style="margin-right:auto">趋势</h2>
          <label>类型
            <select id="series-type">
              <option value="blood_pressure">血压收缩压</option>
              <option value="heart_rate">心率</option>
              <option value="spo2">血氧</option>
              <option value="temperature">温度</option>
              <option value="steps">步数</option>
            </select>
          </label>
        </div>
        <svg id="chart" viewBox="0 0 600 180"></svg>
      </section>
      <section>
        <h2>最近 100 条事件</h2>
        <div id="events"></div>
      </section>
      <section>
        <h2>冲突</h2>
        <p class="note">相同 event_id、不同 payload_hash 时保留第一份回执。</p>
        <div id="conflicts"></div>
      </section>
      <section id="pair-admin" hidden>
        <h2>采集端配对</h2>
        <p class="note">登记采集端后生成 6 位配对码。手机在 10 分钟内输入一次，换取设备令牌。用过即失效。</p>
        <form id="device-form" class="row">
          <label>采集端 ID<input name="device_id" required autocomplete="off"></label>
          <label>名称<input name="name" required autocomplete="off"></label>
          <button type="submit">登记采集端</button>
        </form>
        <form id="pair-form" class="row">
          <label>采集端 ID<input name="device_id" required autocomplete="off"></label>
          <button type="submit">生成配对码</button>
        </form>
        <p id="pair-code" class="code"></p>
        <p id="pair-note" class="note"></p>
      </section>
      <section class="row">
        <button type="button" id="csv">导出 CSV</button>
        <button type="button" id="json">导出 JSON</button>
        <button type="button" id="recon">导出对账 JSON</button>
        <button type="button" id="rq1">RQ1 JSON</button>
        <button type="button" id="rq2">RQ2 JSON</button>
        <button type="button" id="rq3">RQ3 JSON</button>
        <button type="button" id="rq4">RQ4 JSON</button>
      </section>
    </div>
  </main>
  <script>
    const banner = document.querySelector("#banner");
    const tokenKey = "bylw_token";
    const roleKey = "bylw_role";
    function token() { return sessionStorage.getItem(tokenKey) || ""; }
    function role() { return sessionStorage.getItem(roleKey) || ""; }
    function showError(error) { banner.style.display = "block"; banner.textContent = error.message || String(error); }
    function clearError() { banner.style.display = "none"; }
    async function api(path, options) {
      const response = await fetch(path, {
        method: (options && options.method) || "GET",
        headers: Object.assign({ Authorization: "Bearer " + token() }, (options && options.headers) || {}),
        body: options && options.body
      });
      const text = await response.text();
      const data = text ? JSON.parse(text) : null;
      if (response.status === 401) { logout(); throw new Error("请重新登录"); }
      if (!response.ok) throw new Error((data && data.error) || response.statusText);
      return data;
    }
    function cell(text) { const td = document.createElement("td"); td.textContent = text == null ? "" : String(text); return td; }
    function table(headers, rows) {
      const el = document.createElement("table");
      const head = document.createElement("tr");
      headers.forEach((label) => { const th = document.createElement("th"); th.textContent = label; head.append(th); });
      el.append(head);
      rows.forEach((row) => { const tr = document.createElement("tr"); row.forEach((value) => tr.append(cell(value))); el.append(tr); });
      return el;
    }
    function showAdmin() {
      document.querySelector("#pair-admin").hidden = role() !== "admin";
    }
    async function refresh() {
      clearError();
      showAdmin();
      const devices = await api("/api/v1/dashboard/devices");
      const host = document.querySelector("#devices");
      host.replaceChildren();
      if (!devices.length) host.textContent = "还没有登记采集端。";
      devices.forEach((device) => {
        const card = document.createElement("div");
        card.className = "card";
        card.innerHTML = "<strong></strong><div></div><div></div><div></div>";
        card.children[0].textContent = device.name + " (" + device.device_id + ")";
        card.children[1].textContent = (device.sensor_model || "尚无事件") + " · " + (device.operating_state || "未知");
        card.children[2].textContent = device.last_received_at ? "最近回执 " + device.last_received_at : "还没有回执";
        card.children[3].textContent = "冲突 " + device.open_conflicts + " · 重复确认 " + device.duplicate_acks + (device.stale ? " · 同步偏旧" : "");
        if (device.stale) card.children[3].className = "stale";
        host.append(card);
      });
      const events = await api("/api/v1/dashboard/events");
      const eventHost = document.querySelector("#events");
      eventHost.replaceChildren();
      const rows = (events.events || []).map((item) => [
        item.server_received_at, item.event.device_id, item.event.measurement_type, item.event.unit,
        JSON.stringify(item.event.values), item.event.operating_state
      ]);
      eventHost.append(rows.length ? table(["服务器回执时间", "采集端", "类型", "单位", "数值", "运行状态"], rows) : document.createTextNode("还没有事件。"));
      const conflicts = await api("/api/v1/dashboard/conflicts");
      const conflictHost = document.querySelector("#conflicts");
      conflictHost.replaceChildren();
      conflictHost.append(conflicts.length ? table(["时间", "采集端", "event_id", "已保留哈希", "后到哈希"], conflicts.map((row) => [row.at, row.device_id, row.event_id, row.stored_hash, row.presented_hash])) : document.createTextNode("没有冲突。"));
      await drawSeries();
    }
    async function drawSeries() {
      const type = document.querySelector("#series-type").value;
      const points = await api("/api/v1/dashboard/series?type=" + encodeURIComponent(type));
      const svg = document.querySelector("#chart");
      svg.replaceChildren();
      const ordered = [...points].reverse();
      if (ordered.length < 2) {
        const text = document.createElementNS("http://www.w3.org/2000/svg", "text");
        text.setAttribute("x", "16"); text.setAttribute("y", "90"); text.textContent = "至少需要两个点才画趋势。";
        svg.append(text);
        return;
      }
      const values = ordered.map((point) => point.value);
      const min = Math.min(...values), max = Math.max(...values);
      const span = max - min || 1;
      const poly = ordered.map((point, index) => {
        const x = 16 + (index * 568) / (ordered.length - 1);
        const y = 160 - ((point.value - min) / span) * 140;
        return x.toFixed(1) + "," + y.toFixed(1);
      }).join(" ");
      const line = document.createElementNS("http://www.w3.org/2000/svg", "polyline");
      line.setAttribute("fill", "none"); line.setAttribute("stroke", "#0f6e56"); line.setAttribute("stroke-width", "2");
      line.setAttribute("points", poly);
      svg.append(line);
    }
    async function download(path, filename) {
      const response = await fetch(path, { headers: { Authorization: "Bearer " + token() } });
      if (!response.ok) { showError(new Error("导出失败")); return; }
      const blob = await response.blob();
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = filename;
      link.click();
    }
    function logout() {
      sessionStorage.removeItem(tokenKey);
      sessionStorage.removeItem(roleKey);
      document.querySelector("#login").hidden = false;
      document.querySelector("#app").hidden = true;
      document.querySelector("#logout").hidden = true;
    }
    function signedIn(data) {
      sessionStorage.setItem(tokenKey, data.token);
      sessionStorage.setItem(roleKey, data.role || "");
      document.querySelector("#login").hidden = true;
      document.querySelector("#app").hidden = false;
      document.querySelector("#logout").hidden = false;
    }
    document.querySelector("#login-form").addEventListener("submit", async (event) => {
      event.preventDefault();
      const form = new FormData(event.target);
      try {
        const response = await fetch("/api/v1/auth/login", {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ username: form.get("username"), password: form.get("password") })
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || "登录失败");
        signedIn(data);
        await refresh();
      } catch (error) { showError(error); }
    });
    document.querySelector("#device-form").addEventListener("submit", async (event) => {
      event.preventDefault();
      const form = new FormData(event.target);
      try {
        await api("/api/v1/admin/devices", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ device_id: form.get("device_id"), name: form.get("name") })
        });
        document.querySelector("#pair-form").elements.device_id.value = form.get("device_id");
        await refresh();
      } catch (error) { showError(error); }
    });
    document.querySelector("#pair-form").addEventListener("submit", async (event) => {
      event.preventDefault();
      const form = new FormData(event.target);
      const deviceID = String(form.get("device_id") || "");
      try {
        const data = await api("/api/v1/admin/devices/" + encodeURIComponent(deviceID) + "/pairing-codes", { method: "POST" });
        document.querySelector("#pair-code").textContent = data.code;
        document.querySelector("#pair-note").textContent = "采集端 " + data.device_id + " · 10 分钟内有效 · 只能使用一次";
      } catch (error) { showError(error); }
    });
    document.querySelector("#logout").addEventListener("click", logout);
    document.querySelector("#refresh").addEventListener("click", () => refresh().catch(showError));
    document.querySelector("#series-type").addEventListener("change", () => drawSeries().catch(showError));
    document.querySelector("#csv").addEventListener("click", () => download("/api/v1/exports/events.csv", "events.csv"));
    document.querySelector("#json").addEventListener("click", () => download("/api/v1/exports/events.json", "events.json"));
    document.querySelector("#recon").addEventListener("click", () => download("/api/v1/exports/reconciliation.json", "reconciliation.json"));
    document.querySelector("#rq1").addEventListener("click", () => download("/api/v1/exports/rq1.json", "rq1.json"));
    document.querySelector("#rq2").addEventListener("click", () => download("/api/v1/exports/rq2.json", "rq2.json"));
    document.querySelector("#rq3").addEventListener("click", () => download("/api/v1/exports/rq3.json", "rq3.json"));
    document.querySelector("#rq4").addEventListener("click", () => download("/api/v1/exports/rq4.json", "rq4.json"));
    if (token()) {
      document.querySelector("#login").hidden = true;
      document.querySelector("#app").hidden = false;
      document.querySelector("#logout").hidden = false;
      refresh().catch(showError);
    }
  </script>
</body>
</html>
`;
