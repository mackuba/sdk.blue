require 'fileutils'

Jekyll::Hooks.register :site, :post_write do |site|
  source = File.join(site.dest, 'security.txt')
  target = File.join(site.dest, '.well-known', 'security.txt')

  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(source, target)
end
