require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

namespace :cards do
  desc "Regenerate Teams::Cards from the teams.py card models. " \
       "Looks for a teams.py checkout next to this repository; " \
       "set TEAMS_PY_PATH to point elsewhere."
  task :generate do
    teams_py = File.expand_path(ENV.fetch("TEAMS_PY_PATH", "../teams.py"), __dir__)

    unless File.directory?(File.join(teams_py, "packages", "cards"))
      abort <<~MSG
        No teams.py checkout found at #{teams_py}.

        Regenerating the card classes reads the generated Pydantic models in
        Microsoft's Python SDK. Clone it and point TEAMS_PY_PATH at the checkout:

          git clone https://github.com/microsoft/teams.py ../teams.py
          # or, for a custom location:
          TEAMS_PY_PATH=/path/to/teams.py bundle exec rake cards:generate
      MSG
    end

    unless system("uv --version > /dev/null 2>&1")
      abort "uv is required to run the teams.py extractor: https://docs.astral.sh/uv/"
    end

    extractor = File.expand_path("script/extract_cards_ir.py", __dir__)
    sh "uv", "run", "--project", teams_py, "python", extractor
    sh "ruby", File.expand_path("script/generate_cards.rb", __dir__)
  end
end
