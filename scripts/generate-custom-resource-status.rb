#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'

ROOT = ENV.fetch('SOUS_CHEFS_ROOT', File.expand_path('../..', __dir__))
OUTPUT = File.join(ROOT, 'custom-resource-migration-status.html')
DOCS_OUTPUT = File.join(__dir__, '..', 'docs', 'custom-resource-migration-status.html')
PR_DATA = ENV['SOUS_CHEFS_PR_DATA']

STATUS_ORDER = {
  'Needs decision' => 0,
  'No custom resources' => 1,
  'Partial' => 2,
  'Mostly migrated' => 3,
  'Migrated' => 4,
}.freeze

STATUS_CLASS = {
  'Migrated' => 'migrated',
  'Mostly migrated' => 'mostly',
  'Partial' => 'partial',
  'No custom resources' => 'none',
  'Needs decision' => 'review',
}.freeze

DECISION_OVERRIDES = {
  'chef_auto_accumulator' => 'Decide whether its dynamic library framework belongs in the custom resource migration programme.',
  'kubernetes' => 'Decide whether to repair or retire the deliberately disabled pod and service resources.',
  'passenger_apache2' => 'Confirm ownership and product direction before replacing the recipe API.',
  'resharper' => 'Confirm ownership and product direction before replacing the recipe API.',
  'sysinternals' => 'Decide whether the Windows recipe API should migrate or be retired.',
  'unifi' => 'Decide whether the legacy recipe API should migrate or be retired.',
  'vcruntime' => 'Decide whether the Windows recipe API should migrate or be retired.',
  'vim' => 'Decide whether the recipe API should migrate or be retired.',
  'wix' => 'Decide whether the Windows recipe API should migrate or be retired.',
}.freeze

DEPRECATE_OVERRIDES = {
  'bot-trainer' => 'Keep this test-only cookbook out of the production migration programme.',
}.freeze

MIGRATION_PR_PATTERN = /migrat|moderni[sz]|custom.resource|policyfile|unified_mode/i.freeze

def git(path, *args)
  stdout, _stderr, status = Open3.capture3('git', '-C', path, *args)
  status.success? ? stdout : ''
end

def canonical_repo_name(path)
  remote = git(path, 'remote', 'get-url', 'origin').strip
  remote[%r{sous-chefs/([^/]+?)(?:\.git)?\z}, 1] || File.basename(path)
end

def repo_dirs(root)
  Dir.children(root).sort.map do |name|
    path = File.join(root, name)
    next unless File.directory?(path)
    next unless File.exist?(File.join(path, '.git'))
    next unless canonical_repo_name(path) == name

    ref = git(path, 'rev-parse', '--verify', 'origin/main').empty? ? 'HEAD' : 'origin/main'
    files = git(path, 'ls-tree', '-r', '--name-only', ref).lines(chomp: true)
    next unless files.include?('metadata.rb')

    [name, path, ref, files]
  end.compact
end

def rb_count(files, dir)
  files.count { |file| file.start_with?("#{dir}/") && file.end_with?('.rb') }
end

def git_content(path, ref, file)
  git(path, 'show', "#{ref}:#{file}")
end

def public_resources(files)
  files.select do |file|
    file.match?(%r{\Aresources/[^/]+\.rb\z}) && !File.basename(file).start_with?('_')
  end
end

def doc_exists?(files, file)
  files.include?(file)
end

def load_open_prs(path)
  return {} unless path && File.exist?(path)

  prs = File.readlines(path, chomp: true).each_with_object([]) do |line, entries|
    next if line.empty?

    entries << JSON.parse(line, symbolize_names: true)
  end
  prs.group_by { |pr| pr[:repository].sub('sous-chefs/', '') }
end

def structural_metrics(name, path, ref, files, open_prs)
  resources = public_resources(files)
  contents = resources.to_h { |file| [file, git_content(path, ref, file)] }
  searched_files = files.select { |file| file.match?(%r{\A(?:resources|libraries)/.*\.rb\z}) }
  searched_content = searched_files.map { |file| git_content(path, ref, file) }.join("\n")
  recipes = rb_count(files, 'recipes')
  attrs = rb_count(files, 'attributes')
  definitions = rb_count(files, 'definitions')
  providers = rb_count(files, 'providers')
  migration_prs = open_prs.select { |pr| pr[:title].match?(MIGRATION_PR_PATTERN) }

  {
    name: name,
    path: path,
    resources: resources.length,
    unified: contents.count { |_file, content| content.include?('unified_mode true') },
    provides_missing: contents.count { |_file, content| !content.match?(/^provides\b/) },
    frozen_missing: contents.count { |_file, content| !content.lines.first(3).join.include?('frozen_string_literal: true') },
    recipes: recipes,
    attrs: attrs,
    definitions: definitions,
    providers: providers,
    libraries: rb_count(files, 'libraries'),
    documentation: rb_count(files, 'documentation'),
    load_current_resource: searched_content.scan(/\bload_current_resource\b/).length,
    run_action: searched_content.scan(/\.run_action\b/).length,
    global_include: searched_content.scan(/Chef::(?:Resource|DSL::Recipe)\.include/).length,
    lwrp_base: searched_content.scan(/(?:Chef::)?(?:Resource|Provider)::LWRPBase/).length,
    policyfile: files.include?('Policyfile.rb'),
    berksfile: files.include?('Berksfile'),
    migration_doc: doc_exists?(files, 'migration.md'),
    agents_doc: doc_exists?(files, 'AGENTS.md'),
    open_pr_count: open_prs.length,
    migration_prs: migration_prs,
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
  DEPRECATE_OVERRIDES.key?(metrics[:name])
end

def modern_gap_count(metrics)
  metrics.values_at(
    :provides_missing,
    :frozen_missing,
    :load_current_resource,
    :run_action,
    :global_include,
    :lwrp_base
  ).sum
end

def status_for(metrics)
  return 'Needs decision' if needs_decision?(metrics)

  if metrics[:resources].positive?
    return 'Partial' if legacy_surface(metrics).positive? || metrics[:global_include].positive? || metrics[:lwrp_base].positive?
    return 'Mostly migrated' if modern_gap_count(metrics).positive?

    'Migrated'
  elsif legacy_surface(metrics).positive?
    'No custom resources'
  else
    'Needs decision'
  end
end

def next_action_for(metrics, status, flags)
  note = case status
         when 'Migrated'
           metrics[:berksfile] ? 'Resource migration is complete; replace Berksfile with Policyfile.' : 'Resource migration is complete.'
         when 'Mostly migrated'
           'Finish the remaining resource markers or imperative cleanup.'
         when 'Partial'
           'Remove the remaining legacy API or recover the open migration PR.'
         when 'No custom resources'
           'Define the public custom resource API or make an owner decision.'
         when 'Needs decision'
           DECISION_OVERRIDES[metrics[:name]] || 'Confirm ownership and product direction before doing migration work.'
         end

  note = DEPRECATE_OVERRIDES.fetch(metrics[:name], note)

  return note if flags.empty?

  "#{note} Flags: #{flags.join(', ')}."
end

def row_for(metrics)
  status = status_for(metrics)
  flags = []
  flags << 'Decision needed' if needs_decision?(metrics)
  flags << 'Deprecation candidate' if deprecation_candidate?(metrics)
  flags << 'Library-heavy' if metrics[:resources].positive? && metrics[:libraries] >= 10
  flags << (metrics[:policyfile] ? 'Policyfile' : 'Berksfile')
  flags << 'Open migration PR' if metrics[:migration_prs].any?
  migration_blocked = metrics[:migration_prs].any? do |pr|
    failed = (pr[:statusCheckRollup] || []).any? { |check| %w(FAILURE CANCELLED TIMED_OUT).include?(check[:conclusion]) }
    failed || pr[:mergeStateStatus] == 'DIRTY'
  end
  flags << 'Migration PR blocked' if migration_blocked
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
    partial: rows.count { |row| row[:status] == 'Partial' },
    no_resources: rows.count { |row| row[:status] == 'No custom resources' },
    needs_decision: rows.count { |row| row[:status] == 'Needs decision' },
    deprecate: rows.count { |row| row[:flags].include?('Deprecation candidate') },
  }
end

def blocked_pr_reason(pr)
  reasons = []
  reasons << 'merge conflicts' if pr[:mergeStateStatus] == 'DIRTY'
  reasons << "#{pr[:failed_checks]} failed checks" if pr[:failed_checks].positive?
  reasons.join('; ')
end

open_prs = load_open_prs(PR_DATA)
rows = repo_dirs(ROOT).map { |name, path, ref, files| row_for(structural_metrics(name, path, ref, files, open_prs.fetch(name, []))) }
rows.sort_by! { |row| [STATUS_ORDER.fetch(row[:status]), row[:name]] }
summary_data = summary(rows)

decision_rows = rows.select { |row| row[:flags].include?('Decision needed') }
deprecate_rows = rows.select { |row| row[:flags].include?('Deprecation candidate') }
blocked_migration_prs = rows.flat_map do |row|
  row[:migration_prs].each_with_object([]) do |pr, blocked|
    failed = (pr[:statusCheckRollup] || []).count { |check| %w(FAILURE CANCELLED TIMED_OUT).include?(check[:conclusion]) }
    next unless failed.positive? || pr[:mergeStateStatus] == 'DIRTY'

    blocked << pr.merge(repo: row[:name], failed_checks: failed)
  end
end
policyfile_count = rows.count { |row| row[:policyfile] }
berksfile_count = rows.count { |row| row[:berksfile] && !row[:policyfile] }
browser_rows = rows.map do |row|
  {
    name: row[:name],
    status: row[:status],
    statusClass: STATUS_CLASS.fetch(row[:status]),
    dependency: row[:policyfile] ? 'Policyfile' : 'Berksfile',
    flags: row[:flags],
    resources: row[:resources],
    unified: row[:unified],
    modernGaps: modern_gap_count(row),
    recipes: row[:recipes],
    libraries: row[:libraries],
    openPrCount: row[:open_pr_count],
    migrationPrs: row[:migration_prs].map do |pr|
      {
        number: pr[:number],
        url: pr[:url],
        state: pr[:mergeStateStatus],
        failedChecks: (pr[:statusCheckRollup] || []).count { |check| %w(FAILURE CANCELLED TIMED_OUT).include?(check[:conclusion]) },
      }
    end,
    nextAction: row[:next_action],
  }
end

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
        grid-template-columns: repeat(4, minmax(0, 1fr));
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
        grid-template-columns: repeat(3, minmax(0, 1fr));
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

      a {
        color: var(--blue);
        text-decoration-thickness: 1px;
        text-underline-offset: 2px;
      }

      a:hover { color: var(--ink); }

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
        min-width: 1420px;
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

      .pr-links {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
      }

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
          <p class="subtitle">A current inventory of active Sous Chefs cookbooks. It shows custom resource progress, Policyfile adoption, open migration work, and the repositories that need a maintainer decision.</p>
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
        <div class="metric"><b>#{policyfile_count}</b><span>Policyfile</span></div>
        <div class="metric"><b>#{berksfile_count}</b><span>Berksfile only</span></div>
      </section>

      <section class="boards" aria-label="Decision boards">
        <div class="board">
          <h2>Decision Queue</h2>
          <ul>
            #{decision_rows.map { |row| "<li><a href=\"https://github.com/sous-chefs/#{row[:name]}\"><strong>#{row[:name]}</strong></a> <span class=\"muted\">#{DECISION_OVERRIDES.fetch(row[:name], 'Confirm ownership and product direction.')}</span></li>" }.join("\n            ")}
          </ul>
        </div>
        <div class="board">
          <h2>Blocked Migration PRs</h2>
          <ul>
            #{blocked_migration_prs.map { |pr| "<li><a href=\"#{pr[:url]}\"><strong>#{pr[:repo]}##{pr[:number]}</strong></a> <span class=\"muted\">#{blocked_pr_reason(pr)}</span></li>" }.join("\n            ")}
          </ul>
        </div>
        <div class="board">
          <h2>Deprecation Candidate</h2>
          <ul>
            #{deprecate_rows.map { |row| "<li><a href=\"https://github.com/sous-chefs/#{row[:name]}\"><strong>#{row[:name]}</strong></a> <span class=\"muted\">#{DEPRECATE_OVERRIDES.fetch(row[:name])}</span></li>" }.join("\n            ")}
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
            <option value="Policyfile">Policyfile</option>
            <option value="Berksfile">Berksfile</option>
            <option value="Open migration PR">Open migration PR</option>
            <option value="Migration PR blocked">Migration PR blocked</option>
            <option value="Migration doc">Migration doc</option>
            <option value="AGENTS.md">AGENTS.md</option>
          </select>
        </div>
      </section>

      <section class="table-wrap">
        <table id="status-table">
          <thead>
            <tr>
              <th>Cookbook</th>
              <th>Status</th>
              <th>Dependency</th>
              <th>Flags</th>
              <th>Resources</th>
              <th>Unified</th>
              <th>Modern gaps</th>
              <th>Recipes</th>
              <th>Libraries</th>
              <th>Open PRs</th>
              <th>Migration PRs</th>
              <th>Next action</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </section>

      <p class="footnote">Generated by <span class="code">meta/scripts/generate-custom-resource-status.rb</span> on #{Time.now.utc.iso8601} from current default branches and live pull request data. The classification measures migration structure; failed checks are shown separately.</p>
    </main>

    <script>
      const rows = #{JSON.pretty_generate(browser_rows)};

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
            row.dependency,
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
          const migrationPrs = row.migrationPrs.length
            ? row.migrationPrs.map((pr) => {
                const failures = pr.failedChecks ? `, ${pr.failedChecks} failed` : "";
                return `<a href="${pr.url}">#${pr.number}</a><span class="muted"> ${pr.state.toLowerCase()}${failures}</span>`;
              }).join("<br>")
            : '<span class="muted">-</span>';

          tr.innerHTML = `
            <td><a href="https://github.com/sous-chefs/${row.name}"><strong>${row.name}</strong></a></td>
            <td><span class="badge ${row.statusClass}">${row.status}</span></td>
            <td>${row.dependency}</td>
            <td>${flags}</td>
            <td>${row.resources}</td>
            <td>${row.unified}</td>
            <td>${row.modernGaps}</td>
            <td>${row.recipes}</td>
            <td>${row.libraries}</td>
            <td>${row.openPrCount}</td>
            <td>${migrationPrs}</td>
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
