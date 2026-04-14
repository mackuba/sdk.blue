require_relative 'lib/metadata_import'

task :fetch_metadata do
  languages = ENV['LANGUAGE'].to_s.split(',').map(&:strip).reject(&:empty?).uniq
  project = ENV['PROJECT']

  import = MetadataImport.new
  import.run(languages: languages, project: project)
end
