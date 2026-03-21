(function () {
  "use strict";

  var navToggle = document.querySelector("[data-nav-toggle]");
  var nav = document.querySelector("[data-nav]");
  if (navToggle && nav) {
    navToggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        nav.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
      }
    });
  }

  var root = document.querySelector("[data-writing-filters]");
  if (root) {
  var searchInput = root.querySelector("[data-post-search]");
  var statusEl = document.querySelector("[data-filter-status]");
  var postList = document.getElementById("post-list");
  var resultsEl = document.getElementById("search-results");
  var pagination = document.querySelector(".writing-page .pagination");

  if (searchInput && postList) {

  var allPosts = null;
  var selectedTopics = new Set();

  function postsIndexPath() {
    var base = document.documentElement.getAttribute("data-baseurl") || "";
    if (base === "/") base = "";
    base = base.replace(/\/$/, "");
    return (base ? base : "") + "/posts-index.json";
  }

  function loadPosts() {
    if (allPosts) return Promise.resolve(allPosts);
    var url = postsIndexPath();
    return fetch(url, { credentials: "same-origin" })
      .then(function (r) {
        if (!r.ok) throw new Error("index");
        return r.json();
      })
      .then(function (data) {
        allPosts = Array.isArray(data) ? data : [];
        return allPosts;
      })
      .catch(function () {
        allPosts = [];
        return allPosts;
      });
  }

  function norm(s) {
    return String(s || "")
      .toLowerCase()
      .trim();
  }

  function matches(post, q) {
    if (selectedTopics.size > 0) {
      var pt = post.tags || [];
      var topicHit = false;
      selectedTopics.forEach(function (t) {
        if (pt.indexOf(t) !== -1) {
          topicHit = true;
        }
      });
      if (!topicHit) {
        return false;
      }
    }
    var ql = norm(q);
    if (!ql) {
      return selectedTopics.size > 0;
    }
    var blob = [post.title, post.description].concat(post.tags || [], post.categories || []).join(" ").toLowerCase();
    return blob.indexOf(ql) !== -1;
  }

  function renderResults(posts) {
    if (!resultsEl) return;
    resultsEl.innerHTML = "";
    posts.forEach(function (post) {
      var li = document.createElement("li");
      var a = document.createElement("a");
      a.className = "post-card";
      a.href = post.url;

      var dateP = document.createElement("p");
      dateP.className = "post-card__date";
      var time = document.createElement("time");
      time.dateTime = post.date;
      time.textContent = post.date;
      dateP.appendChild(time);

      var h = document.createElement("h2");
      h.className = "post-card__title";
      h.textContent = post.title;

      var ex = document.createElement("p");
      ex.className = "post-card__excerpt";
      ex.textContent = post.description || "";

      a.appendChild(dateP);
      a.appendChild(h);
      a.appendChild(ex);

      if (post.tags && post.tags.length) {
        var tagsEl = document.createElement("div");
        tagsEl.className = "post-card__tags";
        post.tags.slice(0, 4).forEach(function (t) {
          var sp = document.createElement("span");
          sp.className = "tag";
          sp.textContent = t;
          tagsEl.appendChild(sp);
        });
        a.appendChild(tagsEl);
      }

      li.appendChild(a);
      resultsEl.appendChild(li);
    });
  }

  function isFilterActive() {
    return norm(searchInput.value).length > 0 || selectedTopics.size > 0;
  }

  function update() {
    if (!isFilterActive()) {
      if (resultsEl) {
        resultsEl.hidden = true;
        resultsEl.innerHTML = "";
      }
      postList.hidden = false;
      if (pagination) pagination.hidden = false;
      if (statusEl) statusEl.textContent = "";
      return;
    }

    loadPosts().then(function (posts) {
      var q = searchInput.value;
      var filtered = posts.filter(function (p) {
        return matches(p, q);
      });

      if (resultsEl) {
        renderResults(filtered);
        resultsEl.hidden = false;
      }
      postList.hidden = true;
      if (pagination) pagination.hidden = true;

      if (statusEl) {
        statusEl.textContent =
          filtered.length === 0
            ? "No posts match."
            : "Showing " + filtered.length + " post" + (filtered.length === 1 ? "" : "s") + " (all pages).";
      }
    });
  }

  searchInput.addEventListener("input", function () {
    update();
  });

  root.querySelectorAll("[data-filter-tag]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var t = btn.getAttribute("data-filter-tag");
      if (!t) return;
      if (selectedTopics.has(t)) {
        selectedTopics.delete(t);
        btn.setAttribute("aria-pressed", "false");
      } else {
        selectedTopics.add(t);
        btn.setAttribute("aria-pressed", "true");
      }
      update();
    });
  });
  }
  }

  function initDharmaOfWeek() {
    var scriptEl = document.getElementById("dharma-data");
    var sourceEl = document.querySelector("[data-dharma-source]");
    var glossEl = document.querySelector("[data-dharma-gloss]");
    var refEl = document.querySelector("[data-dharma-ref]");
    if (!scriptEl || !sourceEl || !glossEl) return;

    var list;
    try {
      list = JSON.parse(scriptEl.textContent);
    } catch (e) {
      return;
    }
    if (!Array.isArray(list) || !list.length) return;

    var msPerWeek = 7 * 24 * 60 * 60 * 1000;
    var weekNumber = Math.floor(Date.now() / msPerWeek);
    var item = list[weekNumber % list.length];
    var source = item.source || item.text || item.sanskrit || "";
    var gloss = item.gloss || item.translation || "";
    var ref = item.ref || "";

    sourceEl.textContent = source;
    glossEl.textContent = gloss;
    glossEl.hidden = !gloss;

    if (refEl) {
      refEl.textContent = ref;
      refEl.hidden = !ref;
    }
  }

  function initTimelineReveal() {
    var items = document.querySelectorAll(".timeline__item--reveal");
    if (!items.length) return;

    function showAll() {
      items.forEach(function (el) {
        el.classList.add("is-visible");
      });
    }

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      showAll();
      return;
    }

    if (!("IntersectionObserver" in window)) {
      showAll();
      return;
    }

    var obs = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          obs.unobserve(entry.target);
        });
      },
      {
        root: null,
        rootMargin: "0px 0px 12% 0px",
        threshold: 0.08,
      }
    );

    items.forEach(function (el) {
      obs.observe(el);
    });
  }

  function initInPageScroll() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }

    var nav = document.querySelector("[data-nav]");
    var navToggle = document.querySelector("[data-nav-toggle]");
    var header = document.querySelector(".site-header");

    function normalizePath(pathname) {
      var p = pathname || "/";
      p = p.replace(/\/index\.html$/i, "/");
      if (p.length > 1 && p.endsWith("/")) {
        p = p.slice(0, -1);
      }
      return p || "/";
    }

    function sameDocumentLink(anchor) {
      if (!anchor.hash || anchor.hash === "#") {
        return false;
      }
      try {
        var u = new URL(anchor.href, window.location.href);
        if (u.hostname !== window.location.hostname) {
          return false;
        }
        if (u.search !== window.location.search) {
          return false;
        }
        return normalizePath(u.pathname) === normalizePath(window.location.pathname);
      } catch (err) {
        return false;
      }
    }

    document.addEventListener(
      "click",
      function (e) {
        var a = e.target.closest("a[href]");
        if (!a || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) {
          return;
        }
        if (!sameDocumentLink(a)) {
          return;
        }

        var id = decodeURIComponent(a.hash.slice(1));
        if (!id) {
          return;
        }
        var target = document.getElementById(id);
        if (!target) {
          return;
        }

        e.preventDefault();

        if (nav && nav.contains(a)) {
          nav.classList.remove("is-open");
          if (navToggle) {
            navToggle.setAttribute("aria-expanded", "false");
          }
        }

        var headerH = header ? header.getBoundingClientRect().height : 0;
        var offset = headerH + 14;
        var y0 = window.pageYOffset;
        var y1 = target.getBoundingClientRect().top + window.pageYOffset - offset;
        var maxY = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
        y1 = Math.min(Math.max(0, y1), maxY);

        var t0 = null;
        var duration = 640;

        function easeOutCubic(t) {
          return 1 - Math.pow(1 - t, 3);
        }

        function step(ts) {
          if (t0 === null) {
            t0 = ts;
          }
          var t = Math.min(1, (ts - t0) / duration);
          window.scrollTo(0, y0 + (y1 - y0) * easeOutCubic(t));
          if (t < 1) {
            requestAnimationFrame(step);
          } else {
            history.pushState(null, "", window.location.pathname + window.location.search + a.hash);
          }
        }

        requestAnimationFrame(step);
      },
      true
    );
  }

  function initExternalLinksInNewTab() {
    var host = window.location.hostname;
    document.querySelectorAll("a[href]").forEach(function (a) {
      var href = a.getAttribute("href");
      if (!href || href.charAt(0) === "#") return;
      var low = href.trim().toLowerCase();
      if (low.indexOf("javascript:") === 0 || low.indexOf("data:") === 0) return;
      try {
        var u = new URL(href, window.location.href);
        if (u.protocol !== "http:" && u.protocol !== "https:") return;
        if (u.hostname === host) return;
        a.setAttribute("target", "_blank");
        var rel = (a.getAttribute("rel") || "").trim().split(/\s+/).filter(Boolean);
        if (rel.indexOf("noopener") === -1) rel.push("noopener");
        if (rel.indexOf("noreferrer") === -1) rel.push("noreferrer");
        a.setAttribute("rel", rel.join(" "));
      } catch (e) {
        /* ignore */
      }
    });
  }

  function initHeroTypewriter() {
    var el = document.querySelector("[data-hero-type]");
    if (!el) return;
    var full = el.getAttribute("data-type-text") || "";
    if (!full) return;
    var visual = el.closest(".hero__name-visual");
    var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    if (reduced) {
      el.textContent = full;
      if (visual) visual.classList.add("hero__name-visual--visible");
      return;
    }

    el.textContent = "";
    var i = 0;

    function step() {
      if (i >= full.length) return;
      el.textContent += full.charAt(i);
      i++;
      if (visual) visual.classList.add("hero__name-visual--visible");
      var ch = full.charAt(i - 1);
      var delay = ch === " " ? 140 : ch === "," || ch === "." ? 200 : 72 + Math.floor(Math.random() * 36);
      window.setTimeout(step, delay);
    }

    window.setTimeout(step, 280);
  }

  initExternalLinksInNewTab();
  initHeroTypewriter();
  initDharmaOfWeek();
  initTimelineReveal();
  initInPageScroll();
})();
