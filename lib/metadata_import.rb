require_relative 'github_import'
require_relative 'project'
require_relative 'tangled_import'

class MetadataImport
  OUTPUT_FILE = '_data/metadata.yml'
  PROJECTS_DIR = '_data/projects'

  def run(language: nil)
    output_path = File.join(__dir__, '..', OUTPUT_FILE)

    if language
      data = YAML.load_file(output_path, permitted_classes: [Time])
    else
      data = {}
    end

    projects = Project.load_all(language)
    importers = [GithubImport.new, TangledImport.new]

    projects.each do |project|
      project.urls.each do |url|
        if imp = importers.detect { |i| i.url_matches?(url) }
          p url
          data[url] = imp.import_url(url, project)
        else
          puts "Skipping #{url}"
        end
      end
    end

    File.write(output_path, YAML.dump(data))
  end
end
