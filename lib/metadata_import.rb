require_relative 'github_import'

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

    urls = get_repo_urls(language)
    importers = [GithubImport.new]

    urls.each do |url|
      if imp = importers.detect { |i| i.url_matches?(url) }
        p url
        data[url] = imp.import_url(url)
      else
        puts "Skipping #{url}"
      end
    end

    File.write(output_path, YAML.dump(data))
  end

  def get_repo_urls(language = nil)
    yamls = Dir[File.join(__dir__, '..', '_data', 'projects', language ? "#{language}.yml" : '*.yml')]
    yamls.map { |x| YAML.load(File.read(x))['repos'] }.flatten.map { |x| x['url'] }
  end
end
