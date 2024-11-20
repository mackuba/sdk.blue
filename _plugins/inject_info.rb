Jekyll::Hooks.register :site, :post_read do |site|
  data = site.data
  data['projects'].each do |key, section|
    section['repos'].each do |repo|
      repo['info'] = data['github_info'][repo['url']]
    end
  end
end
