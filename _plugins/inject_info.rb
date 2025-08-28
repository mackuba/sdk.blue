def first_nonempty(list)
  list.compact.detect { |x| x.strip.length > 0 }
end

def latest_of(list, field)
  list.compact.sort_by { |x| x[field] }.last
end

def merge_infos(infos)
  {
    'name'         => infos[0]['name'],
    'user_login'   => infos[0]['user_login'],
    'user_profile' => infos[0]['user_profile'],

    'description' => first_nonempty(infos.map { |x| x['description'] }),
    'homepage'    => first_nonempty(infos.map { |x| x['homepage'] }),
    'license'     => first_nonempty(infos.map { |x| x['license'] }),
    'user_name'   => first_nonempty(infos.map { |x| x['user_name'] }),

    'last_release' => latest_of(infos.map { |x| x['last_release'] }, 'published_at'),
    'last_tag'     => latest_of(infos.map { |x| x['last_tag'] }, 'committer_date'),
    'last_commit'  => latest_of(infos.map { |x| x['last_commit'] }, 'committer_date'),

    'stars' => infos.map { |x| x['stars'] || 0 }.reduce(&:+)
  }
end

Jekyll::Hooks.register :site, :post_read do |site|
  data = site.data
  data['projects'].each do |key, section|
    section['repos'].each do |repo|
      if repo['urls']
        repo['info'] = repo['urls'].map { |u| data['metadata'][u] }.then { |x| merge_infos(x) }
      else
        repo['info'] = data['metadata'][repo['url']]
      end
    end
  end
end
