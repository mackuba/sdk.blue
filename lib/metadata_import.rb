require_relative 'github_import'
require_relative 'project'
require_relative 'tangled_import'

class MetadataImport
  OUTPUT_FILE = '_data/metadata.yml'
  PROJECTS_DIR = '_data/projects'

  def run(languages: nil, project: nil)
    languages = nil if languages.is_a?(Array) && languages.empty?
    raise ArgumentError, 'Pass either languages or project, not both' if languages && project

    output_path = File.join(__dir__, '..', OUTPUT_FILE)
    existing_data = YAML.load_file(output_path, permitted_classes: [Time])

    if languages || project
      data = existing_data
    else
      data = {}
    end

    projects = Project.load_all(languages: languages, project: project)
    raise ArgumentError, "No project found for #{project}" if project && projects.empty?

    importers = [GithubImport.new, TangledImport.new]

    projects.each do |project|
      project.urls.each do |url|
        if imp = importers.detect { |i| i.url_matches?(url) }
          p url

          begin
            data[url] = imp.import_url(url, project)
          rescue Minisky::ServerErrorResponse => e
            $stderr.puts "Error fetching #{url}: #{e}"
            data[url] = existing_data[url]
          end
        else
          puts "Skipping #{url}"
        end
      end
    end

    File.write(output_path, YAML.dump(data))
  end
end
