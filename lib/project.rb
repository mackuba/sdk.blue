require 'yaml'

class Project
  def self.load_all(language = nil)
    yamls = Dir[File.join(__dir__, '..', '_data', 'projects', language ? "#{language}.yml" : '*.yml')]
    yamls.map { |y|
      lang = File.basename(y).gsub(/\.yml$/, '')
      YAML.load(File.read(y))['repos'].map { |r| Project.new(r, lang) }
    }.flatten
  end

  attr_reader :language

  def initialize(yaml, language)
    @language = language.to_sym
    @yaml = yaml
  end

  def urls
    @yaml['url'] ? [@yaml['url']] : @yaml['urls']
  end

  def name
    @yaml['name'] || urls.first.gsub(/\/$/, '').split('/').last
  end
end
