require 'yaml'
require_relative 'import_helpers'

class Project
  extend ImportHelpers

  def self.load_all(languages: nil, project: nil)
    return yaml_paths(languages)
      .map { |y|
        lang = File.basename(y).gsub(/\.yml$/, '')
        YAML.load(File.read(y))['repos'].map { |r| Project.new(r, lang) }
      }
      .flatten
      .then { |projects|
        project ? filter_by_url(projects, project) : projects
      }
  end

  def self.yaml_paths(languages)
    if languages
      languages.map { |lang| File.join(__dir__, '..', '_data', 'projects', "#{lang}.yml") }
    else
      Dir[File.join(__dir__, '..', '_data', 'projects', '*.yml')]
    end
  end

  def self.filter_by_url(projects, url)
    normalized_url = normalize_repo_url(url.strip)

    projects.select do |project|
      project.urls.any? { |u| normalize_repo_url(u) == normalized_url }
    end
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
