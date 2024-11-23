require_relative 'github_import'

class MetadataImport
  OUTPUT_FILE = '_data/github_info.yml'
  PROJECTS_DIR = '_data/projects'

  def run
    urls = get_repo_urls
    importers = [GithubImport.new]
    data = {}

    urls.each do |url|
      if imp = importers.detect { |i| i.url_matches?(url) }
        p url
        data[url] = imp.import_url(url)
      else
        puts "Skipping #{url}"
      end
    end

    output_path = File.join(__dir__, '..', OUTPUT_FILE)
    File.write(output_path, YAML.dump(data))
  end

  def get_repo_urls
    yamls = Dir[File.join(__dir__, '..', '_data', 'projects', '*.yml')]
    yamls.map { |x| YAML.load(File.read(x))['repos'] }.flatten.map { |x| x['url'] }
  end
end
