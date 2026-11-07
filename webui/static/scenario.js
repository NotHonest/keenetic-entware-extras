// scenario.js — Russian home screen: EAEU direct, everything else via Keenetic default.
// Does not change Keenetic connection priority and does not touch the vacuum DNS profile.
// Apply only pins geo-split: GEO_ZONE=eas, ROUTE_OUT=<ISP>, ROUTE_IN=br0.
"use strict";

(function () {
    var ZONE = "eas";
    var HOME_IIF = "br0";
    var VACUUM_IIF = "br1";

    var STOCK_LABELS = {
        "Home network": "Домашняя сеть",
        "Home": "Домашняя сеть",
        "Guest network": "Гостевая сеть",
        "Guest": "Гостевая сеть"
    };

    var state = {
        interfaces: null,
        config: null,
        defaults: null,
        ozon: null,
        github: null,
        vacuum: null,
        tunnel: null,
        ispName: "",
        busy: false,
        message: "",
        messageKind: ""
    };

    function esc(s) {
        return EW.escapeHtml(s == null ? "" : String(s));
    }

    function fetchJson(url) {
        return fetch(url, { cache: "no-store" }).then(function (r) {
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.json();
        });
    }

    function soft(url) {
        return fetchJson(url).catch(function (e) {
            return { ok: false, error: (e && e.message) || "ошибка" };
        });
    }

    function pretty(dev) {
        if (!dev) return "неизвестно";
        var raw = EW.ifaceLabelShort(dev);
        return STOCK_LABELS[raw] || raw;
    }

    function pickIsp(data) {
        var list = (data && data.interfaces) || [];
        var cands = [];
        for (var i = 0; i < list.length; i++) {
            var ifc = list[i];
            var name = ifc.name || ifc.id || "";
            if (!name || !ifc.up) continue;
            if (name === "lo" || /^br\d+$/.test(name)) continue;
            if (EW.isTunnelIface(name)) continue;
            if (!/^[a-z0-9_]+$/.test(name) || name.length > 15) continue;
            cands.push(ifc);
        }
        cands.sort(function (a, b) {
            function rank(n) {
                if (/^(eth|ppp|lte|wwan|usb)/.test(n)) return 0;
                return 1;
            }
            var d = rank(a.name) - rank(b.name);
            if (d) return d;
            if (a.label && !b.label) return -1;
            if (!a.label && b.label) return 1;
            return a.name < b.name ? -1 : 1;
        });
        return cands;
    }

    function routeDev(check) {
        if (!check || check.ok === false) return "";
        var routes = check.routes || [];
        if (routes.length && routes[0].dev) return routes[0].dev;
        var devs = check.verdict_devs || [];
        if (devs.length) return devs[0];
        return (check.default_route && check.default_route.dev) || "";
    }

    function defaultDev() {
        var src = state.github && state.github.default_route ? state.github : state.ozon;
        return (src && src.default_route && src.default_route.dev) || "";
    }

    function effectiveConfig() {
        return state.config || {};
    }

    function scenarioPinned(ispName) {
        var cfg = effectiveConfig();
        var out = String(cfg.ROUTE_OUT || "");
        var zone = String(cfg.GEO_ZONE || "");
        var inn = String(cfg.ROUTE_IN || "").replace(/\s+/g, " ").trim();
        return !!ispName && out === ispName && zone === ZONE && inn === HOME_IIF;
    }

    function buildPayload(ispName) {
        var config = state.config || {};
        var defaults = state.defaults || {};
        var keys = {};
        Object.keys(defaults).forEach(function (k) { keys[k] = true; });
        Object.keys(config).forEach(function (k) { keys[k] = true; });
        var desired = {};
        Object.keys(keys).forEach(function (k) { desired[k] = config[k]; });
        desired.GEO_ZONE = ZONE;
        desired.ROUTE_OUT = ispName;
        desired.ROUTE_IN = HOME_IIF;

        var payload = {};
        var changed = false;
        Object.keys(desired).forEach(function (k) {
            var next = desired[k] == null ? "" : String(desired[k]);
            var cur = config[k] == null ? "" : String(config[k]);
            var def = defaults[k] == null ? "" : String(defaults[k]);
            if (next !== cur) changed = true;
            if (next !== def) payload[k] = next;
        });
        return { payload: payload, changed: changed };
    }

    function checkCard(host, check, expect) {
        var dev = routeDev(check);
        var failed = !check || check.ok === false || !dev;
        var label = failed ? "не удалось проверить" : pretty(dev);
        var viaTunnel = !failed && EW.isTunnelIface(dev);
        var note = "";
        var klass = "ew-scenario__check--info";
        if (failed) {
            klass = "ew-scenario__check--bad";
            note = (check && check.error) ? String(check.error) : "роутер не ответил";
        } else if (expect === "direct") {
            klass = viaTunnel ? "ew-scenario__check--bad" : "ew-scenario__check--ok";
            note = viaTunnel ? "ушло в VPN" : "напрямую, зона ЕАЭС";
        } else if (expect === "vpn") {
            klass = viaTunnel ? "ew-scenario__check--ok" : "ew-scenario__check--bad";
            note = viaTunnel ? "через VPN" : "напрямую, не через VPN";
        } else {
            note = viaTunnel ? "вне правила, как основной маршрут" : "вне правила, напрямую";
        }
        return '<div class="ew-scenario__check ' + klass + '">' +
            '<div class="ew-scenario__check-host">' + esc(host) + '</div>' +
            '<div class="ew-scenario__check-path">\u2192 ' + esc(label) + '</div>' +
            '<div class="ew-scenario__check-note">' + esc(note) + '</div>' +
            '</div>';
    }

    function banner(ispName, def) {
        var cfg = effectiveConfig();
        var out = String(cfg.ROUTE_OUT || "auto");
        var defIsTunnel = EW.isTunnelIface(def);
        var outIsTunnel = EW.isTunnelIface(out);
        var outIsAuto = out === "auto" || out === "" || out === "default";
        var html = "";

        if (!ispName) {
            html += '<p class="ew-scenario__warn">Не вижу поднятый интерфейс провайдера. Пока провайдер не в сети, закреплять зону некуда.</p>';
        } else if (outIsAuto && defIsTunnel) {
            html += '<p class="ew-scenario__warn">Зона ЕАЭС стоит в режиме «авто» и повторяет основной маршрут ' +
                esc(pretty(def)) + '. Российские сайты тоже уйдут в VPN. Кнопка ниже закрепит их за ' +
                esc(pretty(ispName)) + '.</p>';
        } else if (outIsTunnel) {
            html += '<p class="ew-scenario__warn">Зона ЕАЭС сейчас явно направлена в ' + esc(pretty(out)) +
                '. Кнопка переключит её на ' + esc(pretty(ispName)) + '.</p>';
        } else if (out !== ispName && !outIsAuto) {
            html += '<p class="ew-scenario__warn">Зона ЕАЭС сейчас выходит через ' + esc(pretty(out)) +
                ', а провайдер — ' + esc(pretty(ispName)) + '.</p>';
        }

        if (def && !defIsTunnel) {
            html += '<p class="ew-scenario__warn">Основной маршрут Keenetic сейчас ' + esc(pretty(def)) +
                ', это не VPN. Зарубежные сайты пойдут напрямую, пока в приоритетах соединений выше не стоит туннель. Эта страница приоритет не меняет.</p>';
        } else if (scenarioPinned(ispName) && defIsTunnel) {
            html += '<p class="ew-scenario__ok">Сценарий включён: сайты ЕАЭС через ' + esc(pretty(ispName)) +
                ', остальное через ' + esc(pretty(def)) + '.</p>';
        }
        return html;
    }

    function tunnelLine(def) {
        var t = state.tunnel;
        if (!t || t.ok === false || !t.dev) {
            return '<p class="ew-scenario__warn">Не удалось проверить, отвечает ли VPN.</p>';
        }
        if (!t.tunnel) {
            return '<p class="ew-scenario__warn">Основной маршрут сейчас ' + esc(pretty(t.dev)) +
                '. Это не VPN, поэтому проверять туннель нечего, и зарубежный DNS спрашивает напрямую.</p>';
        }
        var name = pretty(t.dev || def);
        if (t.reachable && t.dns_direct) {
            return '<p class="ew-scenario__ok">' + esc(name) + ' снова отвечает. Зарубежный DNS ещё минуту может идти напрямую, потом вернётся в туннель.</p>';
        }
        if (t.reachable) {
            return '<p class="ew-scenario__ok">' + esc(name) + ' отвечает. Зарубежный DNS идёт через него. Если туннель замолчит, DNS через пару минут спросит провайдера напрямую.</p>';
        }
        if (t.dns_direct) {
            return '<p class="ew-scenario__warn">' + esc(name) + ' молчит. Зарубежные сайты могут не открываться, пока Keenetic держит его основным маршрутом. Зарубежный DNS временно спрашивает провайдера напрямую.</p>';
        }
        return '<p class="ew-scenario__warn">' + esc(name) + ' молчит. Зарубежный DNS ещё через него. Если так продлится пару минут, DNS перейдёт на провайдера. Маршрут Keenetic страница не переключает.</p>';
    }

    function render() {
        var root = document.getElementById("scenario");
        if (!root) return;

        var cands = pickIsp(state.interfaces);
        if (!state.ispName || !cands.some(function (c) { return c.name === state.ispName; })) {
            state.ispName = cands.length ? cands[0].name : "";
        }
        var ispName = state.ispName;
        var def = defaultDev();
        var pinned = scenarioPinned(ispName);
        var plan = ispName ? buildPayload(ispName) : { changed: false, payload: {} };
        var homeLabel = pretty(HOME_IIF);
        var vacuumLabel = pretty(VACUUM_IIF);
        var restLabel = def ? pretty(def) : "основной маршрут Keenetic";

        var ispSelect = "";
        if (cands.length > 1) {
            ispSelect = '<label class="ew-scenario__field">Провайдер<select class="ew-scenario__select" data-scenario-isp>';
            for (var i = 0; i < cands.length; i++) {
                var c = cands[i];
                ispSelect += '<option value="' + esc(c.name) + '"' + (c.name === ispName ? " selected" : "") + '>' +
                    esc(pretty(c.name)) + '</option>';
            }
            ispSelect += '</select></label>';
        }

        var btnLabel = state.busy ? "Сохраняю…" : (pinned && !plan.changed ? "Уже так настроено" : "Закрепить ЕАЭС за " + pretty(ispName || "провайдером"));
        var btnDisabled = state.busy || !ispName || !state.config || (pinned && !plan.changed);

        root.innerHTML =
            '<h2 class="ew-scenario__title">ЕАЭС напрямую, остальное в VPN</h2>' +
            '<p class="ew-scenario__lead">Домашняя сеть: российские сайты через провайдера, всё остальное — туда, куда Keenetic отправил основной маршрут. Сейчас это ' +
            esc(restLabel) + '.</p>' +
            '<div class="ew-scenario__grid">' +
                checkCard("ozon.ru · " + homeLabel, state.ozon, "direct") +
                checkCard("github.com · " + homeLabel, state.github, "vpn") +
                checkCard(vacuumLabel, state.vacuum, "info") +
            '</div>' +
            banner(ispName, def) +
            tunnelLine(def) +
            '<div class="ew-scenario__fields">' +
                '<div class="ew-scenario__field"><div class="ew-scenario__field-label">Напрямую</div><div class="ew-scenario__field-value">ЕАЭС</div><div class="ew-scenario__field-hint">Россия, Беларусь, Казахстан, Армения, Киргизия</div></div>' +
                '<div class="ew-scenario__field"><div class="ew-scenario__field-label">Остальное</div><div class="ew-scenario__field-value">' + esc(restLabel) + '</div><div class="ew-scenario__field-hint">Задаётся приоритетом соединений в Keenetic</div></div>' +
                '<div class="ew-scenario__field"><div class="ew-scenario__field-label">Где действует</div><div class="ew-scenario__field-value">' + esc(homeLabel) + '</div><div class="ew-scenario__field-hint">' + esc(vacuumLabel) + ' в правило не входит</div></div>' +
                ispSelect +
            '</div>' +
            '<div class="ew-scenario__actions">' +
                '<button type="button" class="ndw-button ndw-button--toggle ndw-button--toggle-enabled ndw-button--small" data-scenario-apply' + (btnDisabled ? " disabled" : "") + '>' + esc(btnLabel) + '</button>' +
                '<button type="button" class="ndw-button ndw-button--toggle ndw-button--small" data-scenario-refresh' + (state.busy ? " disabled" : "") + '>Проверить ещё раз</button>' +
                '<button type="button" class="ndw-button ndw-button--toggle ndw-button--small" data-scenario-advanced>Дополнительно</button>' +
                (state.message ? '<span class="ew-scenario__status ew-scenario__status--' + esc(state.messageKind) + '">' + esc(state.message) + '</span>' : '') +
            '</div>' +
            '<p class="ew-scenario__fine">Кнопка не меняет приоритет соединений Keenetic и не трогает DNS сегмента пылесоса. Зарубежный трафик идёт туда, куда смотрит основной маршрут. Если VPN замолчит, зарубежный DNS через пару минут перейдёт на провайдера сам, а маршрут Keenetic эта страница не переключает.</p>';
    }

    function load() {
        var root = document.getElementById("scenario");
        if (root && !state.config) {
            root.innerHTML = '<p class="ew-scenario__lead">Проверяю, куда сейчас идут ozon.ru и github.com…</p>';
        }
        Promise.all([
            soft("/api/system/interfaces"),
            soft("/api/geo-split/config"),
            soft("/api/geo-split/route-check?host=ozon.ru&from=br0"),
            soft("/api/geo-split/route-check?host=github.com&from=br0"),
            soft("/api/geo-split/route-check?host=github.com&from=br1"),
            soft("/api/geo-split/tunnel-check")
        ]).then(function (rows) {
            state.interfaces = rows[0] && rows[0].ok !== false ? rows[0] : { interfaces: [] };
            if (rows[1] && rows[1].config) {
                state.config = rows[1].config;
                state.defaults = rows[1].defaults || {};
            }
            state.ozon = rows[2];
            state.github = rows[3];
            state.vacuum = rows[4];
            state.tunnel = rows[5];
            state.busy = false;
            render();
        });
    }

    function apply() {
        var ispName = state.ispName;
        if (!ispName || !state.config || state.busy) return;
        if (!/^[a-z0-9_]+$/.test(ispName)) return;
        var plan = buildPayload(ispName);
        if (!plan.changed) {
            state.message = "Менять нечего: ЕАЭС уже закреплён за " + pretty(ispName) + ".";
            state.messageKind = "ok";
            render();
            return;
        }
        state.busy = true;
        state.message = "Перечитываю маршруты. Это займёт несколько секунд.";
        state.messageKind = "";
        render();
        fetch("/api/geo-split/config", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(plan.payload)
        }).then(function (r) { return r.json(); }).then(function (data) {
            if (!data || data.ok === false) {
                state.busy = false;
                state.message = "Не сохранилось" + (data && data.error ? ": " + data.error : ".");
                state.messageKind = "bad";
                render();
                return;
            }
            if (data.restarted === false) {
                state.message = "Записано, но служба не перезапустилась.";
                state.messageKind = "bad";
            } else {
                state.message = "Готово. ЕАЭС закреплён за " + pretty(ispName) + ".";
                state.messageKind = "ok";
            }
            setTimeout(load, 2500);
        }).catch(function (e) {
            state.busy = false;
            state.message = (e && e.message) || "Нет ответа от роутера.";
            state.messageKind = "bad";
            render();
        });
    }

    function onClick(e) {
        var t = e.target;
        if (!t || !t.closest) return;
        if (t.closest("[data-scenario-apply]")) {
            apply();
            return;
        }
        if (t.closest("[data-scenario-refresh]")) {
            state.message = "";
            load();
            return;
        }
        if (t.closest("[data-scenario-advanced]")) {
            if (typeof openConfigModal === "function") openConfigModal("geo-split");
        }
    }

    function onChange(e) {
        var sel = e.target && e.target.closest ? e.target.closest("[data-scenario-isp]") : null;
        if (!sel) return;
        state.ispName = sel.value;
        state.message = "";
        render();
    }

    document.addEventListener("DOMContentLoaded", function () {
        var root = document.getElementById("scenario");
        if (!root) return;
        root.addEventListener("click", onClick);
        root.addEventListener("change", onChange);
        if (EW.loadIfaceMap) {
            EW.loadIfaceMap().then(load, load);
        } else {
            load();
        }
    });
})();
