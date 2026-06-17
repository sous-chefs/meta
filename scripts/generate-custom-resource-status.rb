#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'

ROOT = File.expand_path('../..', __dir__)
OUTPUT = File.join(ROOT, 'custom-resource-migration-status.html')
DOCS_OUTPUT = File.join(__dir__, '..', 'docs', 'custom-resource-migration-status.html')

STATUS_ORDER = {
  'Needs decision' => 0,
  'No custom resources yet' => 1,
  'Partial / legacy cleanup' => 2,
  'Mostly migrated' => 3,
  'Migrated' => 4,
}.freeze

STATUS_CLASS = {
  'Migrated' => 'migrated',
  'Mostly migrated' => 'mostly',
  'Partial / legacy cleanup' => 'partial',
  'No custom resources yet' => 'none',
  'Needs decision' => 'review',
}.freeze

DECISION_OVERRIDES = {
  'netplan' => 'No public cookbook surface remains locally. Decide whether to archive it or redefine it with an explicit resource API.',
  'chef_auto_accumulator' => 'This repo is still dominated by library code with only a thin resource wrapper. Decide whether it belongs in the migration program or needs a different lifecycle.',
}.freeze

def repo_dirs(root)
  Dir.children(root).sort.map do |name|
    path = File.join(root, name)
    next unless File.directory?(path)
    next unless File.exist?(File.join(path, 'metadata.rb'))

    [name, path]
  end.compact
end

def rb_count(path, dir)
  full = File.join(path, dir)
  return 0 unless Dir.exist?(full)

  Dir.glob(File.join(full, '**', '*.rb')).count
end

def unified_count(path)
  resources_dir = File.join(path, 'resources')
  return 0 unless Dir.exist?(resources_dir)

  Dir.glob(File.join(resources_dir, '**', '*.rb')).count do |file|
    File.read(file).include?('unified_mode true')
  end
end

def doc_exists?(path, file)
  File.exist?(File.join(path, file))
end

def structural_metrics(name, path)
  resources = rb_count(path, 'resources')
  unified = unified_count(path)
  recipes = rb_count(path, 'recipes')
  attrs = rb_count(path, 'attributes')
  definitions = rb_count(path, 'definitions')
  providers = rb_count(path, 'providers')
  libraries = rb_count(path, 'libraries')
  docs = rb_count(path, 'documentation')

  {
    name: name,
    path: path,
    resources: resources,
    unified: unified,
    recipes: recipes,
    attrs: attrs,
    definitions: definitions,
    providers: providers,
    libraries: libraries,
    documentation: docs,
    migration_doc: doc_exists?(path, 'migration.md'),
    agents_doc: doc_exists?(path, 'AGENTS.md'),
  }
end

def legacy_surface(metrics)
  metrics[:recipes] + metrics[:attrs] + metrics[:definitions] + metrics[:providers]
end

def needs_decision?(metrics)
  return true if DECISION_OVERRIDES.key?(metrics[:name])
  return true if metrics[:resources].zero? && legacy_surface(metrics).zero?
  return true if metrics[:resources] <= 1 && legacy_surface(metrics).zero? && metrics[:libraries] >= 10

  false
end

def deprecation_candidate?(metrics)
  return false unless metrics[:resources].zero?
  return false if metrics[:migration_doc]

  thin_legacy = metrics[:recipes] <= 4 && metrics[:attrs] <= 2 && metrics[:definitions].zero? && metrics[:providers].zero?
  sparse_supporting_code = metrics[:libraries].zero? && metrics[:documentation].zero?

  thin_legacy || sparse_supporting_code
end

def status_for(metrics)
  return 'Needs decision' if needs_decision?(metrics)

  if metrics[:resources].positive?
    case legacy_surface(metrics)
    when 0
      'Migrated'
    when 1, 2
      'Mostly migrated'
    else
      'Partial / legacy cleanup'
    end
  elsif legacy_surface(metrics).positive?
    'No custom resources yet'
  else
    'Needs decision'
  end
end

def next_action_for(metrics, status, flags)
  note = case status
         when 'Migrated'
           if metrics[:libraries] >= 8
             'Resource-first, but library-heavy. Maintain and only revisit when refactoring internal helpers.'
           else
             'Resource-first. Maintain and spot-check ChefSpec/Kitchen when changing behavior.'
           end
         when 'Mostly migrated'
           'Finish the last recipe/attribute/provider holdouts or make the compatibility surface explicit.'
         when 'Partial / legacy cleanup'
           'Remove the remaining legacy root API and supporting provider/definition code before calling this done.'
         when 'No custom resources yet'
           'Define the public custom resource API, or make a deprecation/archive call if this cookbook is too thin.'
         when 'Needs decision'
           DECISION_OVERRIDES[metrics[:name]] || 'Confirm ownership and product direction before doing migration work.'
         end

  return note if flags.empty?

  "#{note} Flags: #{flags.join(', ')}."
end

def row_for(metrics)
  status = status_for(metrics)
  flags = []
  flags << 'Decision needed' if needs_decision?(metrics)
  flags << 'Deprecation candidate' if deprecation_candidate?(metrics)
  flags << 'Library-heavy' if metrics[:resources].positive? && metrics[:libraries] >= 10
  flags << 'Migration doc' if metrics[:migration_doc]
  flags << 'AGENTS.md' if metrics[:agents_doc]

  metrics.merge(
    status: status,
    flags: flags,
    next_action: next_action_for(metrics, status, flags)
  )
end

def summary(rows)
  {
    total: rows.length,
    migrated: rows.count { |row| row[:status] == 'Migrated' },
    mostly: rows.count { |row| row[:status] == 'Mostly migrated' },
    partial: rows.count { |row| row[:status] == 'Partial / legacy cleanup' },
    no_resources: rows.count { |row| row[:status] == 'No custom resources yet' },
    needs_decision: rows.count { |row| row[:status] == 'Needs decision' },
    deprecate: rows.count { |row| row[:flags].include?('Deprecation candidate') },
  }
end

rows = repo_dirs(ROOT).map { |name, path| row_for(structural_metrics(name, path)) }
rows.sort_by! { |row| [STATUS_ORDER.fetch(row[:status]), row[:name]] }
summary_data = summary(rows)

decision_rows = rows.select { |row| row[:flags].include?('Decision needed') }
deprecate_rows = rows.select { |row| row[:flags].include?('Deprecation candidate') }

html = <<~HTML
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Sous Chefs Custom Resource Status</title>
    <style>
      :root {
        --bg: #f3efe7;
        --paper: #fffdf8;
        --ink: #17202b;
        --muted: #667085;
        --line: #d8cfbf;
        --green: #166448;
        --green-bg: #def5ea;
        --blue: #0d5e92;
        --blue-bg: #e2f0fb;
        --amber: #9a5b00;
        --amber-bg: #fff0cb;
        --red: #9f372d;
        --red-bg: #ffe2dd;
        --violet: #61479d;
        --violet-bg: #ece6ff;
        --slate: #3e4b5c;
        --slate-bg: #e9edf2;
        --shadow: 0 20px 44px rgba(23, 32, 43, 0.08);
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        color: var(--ink);
        background:
          linear-gradient(90deg, rgba(23, 32, 43, 0.035) 1px, transparent 1px),
          linear-gradient(180deg, rgba(23, 32, 43, 0.035) 1px, transparent 1px),
          var(--bg);
        background-size: 26px 26px;
        font-family: "Avenir Next", Avenir, "Segoe UI", sans-serif;
      }

      main {
        width: min(1320px, calc(100% - 32px));
        margin: 0 auto;
        padding: 36px 0 56px;
      }

      header {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 240px;
        gap: 24px;
        align-items: end;
        margin-bottom: 22px;
      }

      h1 {
        margin: 0;
        max-width: 860px;
        font-family: Georgia, "Times New Roman", serif;
        font-size: clamp(36px, 6vw, 72px);
        line-height: 0.96;
      }

      .subtitle {
        margin: 14px 0 0;
        max-width: 860px;
        color: var(--muted);
        font-size: 16px;
        line-height: 1.5;
      }

      .stamp {
        border: 1px solid var(--line);
        border-radius: 12px;
        padding: 14px 16px;
        background: rgba(255, 253, 248, 0.82);
        box-shadow: var(--shadow);
      }

      .stamp span {
        display: block;
        color: var(--muted);
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.09em;
      }

      .stamp strong {
        display: block;
        margin-top: 6px;
        font-size: 34px;
        line-height: 1;
      }

      .summary {
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
        gap: 12px;
        margin-bottom: 16px;
      }

      .metric {
        background: var(--paper);
        border: 1px solid var(--line);
        border-radius: 12px;
        padding: 16px;
        box-shadow: 0 10px 24px rgba(23, 32, 43, 0.05);
      }

      .metric b {
        display: block;
        font-size: 30px;
        line-height: 1;
        margin-bottom: 8px;
      }

      .metric span {
        color: var(--muted);
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.06em;
      }

      .boards {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 14px;
        margin-bottom: 16px;
      }

      .board {
        background: var(--paper);
        border: 1px solid var(--line);
        border-radius: 12px;
        box-shadow: var(--shadow);
        padding: 16px;
      }

      .board h2 {
        margin: 0 0 10px;
        font-size: 15px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
      }

      .board ul {
        margin: 0;
        padding-left: 18px;
        color: var(--muted);
      }

      .board li + li {
        margin-top: 6px;
      }

      .controls {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        background: var(--paper);
        border: 1px solid var(--line);
        border-radius: 12px;
        padding: 12px;
        margin-bottom: 14px;
      }

      .control-group {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
        align-items: center;
      }

      input, select {
        min-height: 42px;
        border: 1px solid var(--line);
        border-radius: 9px;
        background: #fff;
        color: var(--ink);
        padding: 0 12px;
        font: inherit;
      }

      input {
        min-width: min(360px, 100%);
      }

      .table-wrap {
        overflow: auto;
        background: var(--paper);
        border: 1px solid var(--line);
        border-radius: 12px;
        box-shadow: var(--shadow);
      }

      table {
        width: 100%;
        min-width: 1160px;
        border-collapse: collapse;
      }

      th, td {
        padding: 11px 12px;
        border-bottom: 1px solid #ece4d6;
        text-align: left;
        vertical-align: top;
        font-size: 13px;
      }

      th {
        position: sticky;
        top: 0;
        background: #efe5d5;
        color: #3d4654;
        text-transform: uppercase;
        font-size: 11px;
        letter-spacing: 0.07em;
      }

      tbody tr:hover {
        background: #fff8eb;
      }

      tr:last-child td {
        border-bottom: 0;
      }

      .badge, .flag {
        display: inline-flex;
        align-items: center;
        min-height: 24px;
        border-radius: 999px;
        padding: 3px 10px;
        font-size: 12px;
        font-weight: 700;
        white-space: nowrap;
      }

      .migrated { color: var(--green); background: var(--green-bg); }
      .mostly { color: var(--blue); background: var(--blue-bg); }
      .partial { color: var(--amber); background: var(--amber-bg); }
      .none { color: var(--red); background: var(--red-bg); }
      .review { color: var(--violet); background: var(--violet-bg); }
      .flag {
        margin: 0 6px 6px 0;
        color: var(--slate);
        background: var(--slate-bg);
      }

      .code {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        background: #f2eadc;
        border: 1px solid #e1d7c5;
        border-radius: 6px;
        padding: 1px 5px;
      }

      .footnote {
        margin-top: 14px;
        color: var(--muted);
        font-size: 13px;
      }

      .muted { color: var(--muted); }

      @media (max-width: 980px) {
        header, .summary, .boards {
          grid-template-columns: 1fr;
        }

        h1 { font-size: 42px; }
      }
    </style>
  </head>
  <body>
    <main>
      <header>
        <div>
          <h1>Custom resource status board</h1>
          <p class="subtitle">Structural inventory for Sous Chefs cookbooks in <span class="code">/Users/damacus/repos/sous-chefs</span>. This rebuild is generated from the local checkout, with explicit slices for resource-first repos, legacy cleanup, decision queue, and deprecation candidates.</p>
        </div>
        <div class="stamp">
          <span>Total cookbooks</span>
          <strong>#{summary_data[:total]}</strong>
        </div>
      </header>

      <section class="summary" aria-label="Status summary">
        <div class="metric"><b>#{summary_data[:migrated]}</b><span>Migrated</span></div>
        <div class="metric"><b>#{summary_data[:mostly]}</b><span>Mostly migrated</span></div>
        <div class="metric"><b>#{summary_data[:partial]}</b><span>Legacy cleanup</span></div>
        <div class="metric"><b>#{summary_data[:no_resources]}</b><span>No custom resources</span></div>
        <div class="metric"><b>#{summary_data[:needs_decision]}</b><span>Decision queue</span></div>
        <div class="metric"><b>#{summary_data[:deprecate]}</b><span>Deprecate candidate</span></div>
      </section>

      <section class="boards" aria-label="Decision boards">
        <div class="board">
          <h2>Decision Queue</h2>
          <ul>
            #{decision_rows.map { |row| "<li><strong>#{row[:name]}</strong> <span class=\"muted\">#{row[:next_action]}</span></li>" }.join("\n            ")}
          </ul>
        </div>
        <div class="board">
          <h2>Deprecation Candidates</h2>
          <ul>
            #{deprecate_rows.map { |row| "<li><strong>#{row[:name]}</strong> <span class=\"muted\">#{row[:next_action]}</span></li>" }.join("\n            ")}
          </ul>
        </div>
      </section>

      <section class="controls" aria-label="Table controls">
        <div class="control-group">
          <input id="search" type="search" placeholder="Filter by cookbook, flag, or action">
          <select id="status">
            <option value="">All statuses</option>
            #{STATUS_ORDER.keys.map { |status| "<option value=\"#{status}\">#{status}</option>" }.join("\n            ")}
          </select>
          <select id="flag">
            <option value="">All flags</option>
            <option value="Decision needed">Decision needed</option>
            <option value="Deprecation candidate">Deprecation candidate</option>
            <option value="Library-heavy">Library-heavy</option>
            <option value="Migration doc">Migration doc</option>
            <option value="Limitations doc">Limitations doc</option>
          </select>
        </div>
      </section>

      <section class="table-wrap">
        <table id="status-table">
          <thead>
            <tr>
              <th>Cookbook</th>
              <th>Status</th>
              <th>Flags</th>
              <th>Resources</th>
              <th>Unified</th>
              <th>Recipes</th>
              <th>Attrs</th>
              <th>Defs</th>
              <th>Providers</th>
              <th>Libraries</th>
              <th>Next action</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </section>

      <p class="footnote">Generated by <span class="code">meta/scripts/generate-custom-resource-status.rb</span> on #{Time.now.utc.iso8601}. Classification is structural triage from the local checkout, not a test pass/fail signal.</p>
    </main>

    <script>
      const rows = #{JSON.pretty_generate(rows.map { |row|
        {
          name: row[:name],
          status: row[:status],
          statusClass: STATUS_CLASS.fetch(row[:status]),
          flags: row[:flags],
          resources: row[:resources],
          unified: row[:unified],
          recipes: row[:recipes],
          attrs: row[:attrs],
          definitions: row[:definitions],
          providers: row[:providers],
          libraries: row[:libraries],
          nextAction: row[:next_action]
        }
      })};

      const tbody = document.querySelector("#status-table tbody");
      const search = document.querySelector("#search");
      const status = document.querySelector("#status");
      const flag = document.querySelector("#flag");

      function render() {
        const term = search.value.trim().toLowerCase();
        const statusValue = status.value;
        const flagValue = flag.value;

        const filtered = rows.filter((row) => {
          if (statusValue && row.status !== statusValue) return false;
          if (flagValue && !row.flags.includes(flagValue)) return false;

          if (!term) return true;

          const haystack = [
            row.name,
            row.status,
            row.flags.join(" "),
            row.nextAction,
          ].join(" ").toLowerCase();

          return haystack.includes(term);
        });

        tbody.innerHTML = "";

        filtered.forEach((row) => {
          const tr = document.createElement("tr");
          const flags = row.flags.length
            ? row.flags.map((entry) => `<span class="flag">${entry}</span>`).join("")
            : '<span class="muted">-</span>';

          tr.innerHTML = `
            <td><strong>${row.name}</strong></td>
            <td><span class="badge ${row.statusClass}">${row.status}</span></td>
            <td>${flags}</td>
            <td>${row.resources}</td>
            <td>${row.unified}</td>
            <td>${row.recipes}</td>
            <td>${row.attrs}</td>
            <td>${row.definitions}</td>
            <td>${row.providers}</td>
            <td>${row.libraries}</td>
            <td>${row.nextAction}</td>
          `;
          tbody.appendChild(tr);
        });
      }

      [search, status, flag].forEach((node) => node.addEventListener("input", render));
      render();
    </script>
  </body>
  </html>
HTML

[OUTPUT, DOCS_OUTPUT].each do |output|
  File.write(output, html)
  puts "Wrote #{output}"
end
