require_relative 'github_import'
require_relative 'project'
require_relative 'tangled_import'

class MetadataImport
  OUTPUT_FILE = '_data/metadata.yml'
  PROJECTS_DIR = '_data/projects'

  def run(languages: nil, project: nil, threads: 1)
    languages = nil if languages.is_a?(Array) && languages.empty?
    raise ArgumentError, 'Pass either languages or project, not both' if languages && project
    raise ArgumentError, 'THREADS must be a positive integer' unless threads.is_a?(Integer) && threads.positive?

    output_path = File.join(__dir__, '..', OUTPUT_FILE)
    existing_data = YAML.load_file(output_path, permitted_classes: [Time])

    if languages || project
      data = existing_data
    else
      data = {}
    end

    projects = Project.load_all(languages: languages, project: project)
    raise ArgumentError, "No project found for #{project}" if project && projects.empty?

    results = fetch_data(projects, threads)
    results.each do |url, value|
      data[url] = (value == :error) ? existing_data[url] : value
    end

    File.write(output_path, YAML.dump(data.sort.to_h))
  end


  private

  def fetch_data(projects, n_threads)
    jobs = make_job_queue(projects)

    results = {}
    mutex = Mutex.new
    errors = Queue.new

    process_jobs = proc do
      importers = [GithubImport.new, TangledImport.new]

      while job = jobs.pop
        url, project = job

        if importer = importers.detect { |i| i.url_matches?(url) }
          value = fetch_url(url, project, importer)

          mutex.synchronize {
            results[url] = value
          }
        else
          puts "Skipping #{url}"
        end
      end
    rescue StandardError => e
      errors << e
      jobs.clear
    end

    if n_threads == 1
      process_jobs.call
    else
      threads = (0...n_threads).map do
        Thread.new(&process_jobs)
      end

      threads.each(&:join)
    end

    if !errors.empty?
      error = errors.pop
      raise error
    end

    results
  end

  def make_job_queue(projects)
    jobs = Queue.new

    projects.each do |project|
      project.urls.each { |url| jobs << [url, project] }
    end

    jobs.close
    jobs
  end

  def fetch_url(url, project, importer)
    puts url
    importer.import_url(url, project)
  rescue FetchError => e
    $stderr.puts "Error fetching #{url}: #{e}"
    :error
  end
end
