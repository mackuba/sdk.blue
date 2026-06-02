require_relative 'lib/metadata_import'
require 'didkit'

Encoding.default_external = 'UTF-8'

task :fetch_metadata do
  languages = ENV['LANGUAGE'].to_s.split(',').map(&:strip).reject(&:empty?).uniq
  project = ENV['PROJECT']

  import = MetadataImport.new
  import.run(languages: languages, project: project)
end

task :normalize_tangled_urls do
  urls = %x(grep -ohER "https://tangled.org/[a-zA-Z0-9\\-\\.]+/[a-zA-Z0-9_\\-\\.]+/?" _data/projects | sort | uniq).lines.map(&:strip)
  dids = {}

  urls.each do |url|
    handle = url.split('/')[3]
    dids[handle] ||= DID.resolve_handle(handle).did
  end

  Dir['_data/projects/*.yml'].each do |file|
    text = File.read(file)

    urls.each do |url|
      handle = url.split('/')[3]
      normalized = url.sub(handle, dids[handle]).chomp('/')
      text.gsub!(url, normalized)
    end

    File.write(file, text)
  end
end
