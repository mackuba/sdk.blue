require_relative 'lib/metadata_import'

task :fetch_metadata do
  import = MetadataImport.new
  import.run(language: ENV['LANGUAGE'])
end
