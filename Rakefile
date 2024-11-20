require 'json'
require 'net/http'
require 'yaml'

task :update_metadata do
  yamls = Dir['_data/projects/*.yml']
  urls = yamls.map { |x| YAML.load(File.read(x))['repos'] }.flatten.map { |x| x['url'] }
  config = YAML.load(File.read('config/auth.yml'))

  data = {}
  users = {}
  hh = { 'Authorization' => 'Bearer ' + config['github_token'] }

  urls.each do |url|
    p url
    if url =~ %r{^https://github\.com/([\w\-\.]+)/([\w\-\.]+)}
      user, repo = $1, $2
      response = Net::HTTP.get_response(URI("https://api.github.com/repos/#{user}/#{repo}"), hh)

      if response.code.to_i == 200
        json = JSON.parse(response.body)

        data[url] = {
          'name' => json['name'],
          'description' => json['description'],
          'user_login' => json['owner']['login'],
          'homepage' => json['homepage'],
          'stars' => json['stargazers_count'],
          'license' => json['license'] && json['license']['spdx_id']
        }

        response = Net::HTTP.get_response(URI("https://api.github.com/repos/#{user}/#{repo}/releases/latest"), hh)

        if response.code.to_i == 200
          json = JSON.parse(response.body)

          data[url]['last_release'] = {
            'tag_name' => json['tag_name'],
            'name' => json['name'],
            'draft' => json['draft'],
            'prerelease' => json['prerelease'],
            'created_at' => json['created_at'],
            'published_at' => json['published_at']
          }
        elsif response.code.to_i != 404
          puts "Invalid response for #{response.uri}: #{response}"
        end

        response = Net::HTTP.get_response(URI("https://api.github.com/repos/#{user}/#{repo}/tags"), hh)

        if response.code.to_i == 200
          json = JSON.parse(response.body)[0]

          if json
            name = json['name']
            response = Net::HTTP.get_response(URI(json['commit']['url']))
            if response.code.to_i == 200
              json = JSON.parse(response.body)
              data[url]['last_tag'] = {
                'name' => name,
                'author_date' => json['commit']['author']['date'],
                'committer_date' => json['commit']['committer']['date']
              }
            else
              puts "Invalid response for #{response.uri}: #{response}"
            end
          end
        elsif response.code.to_i != 404
          puts "Invalid response for #{response.uri}: #{response}"
        end

        response = Net::HTTP.get_response(URI("https://api.github.com/repos/#{user}/#{repo}/commits"), hh)

        if response.code.to_i == 200
          json = JSON.parse(response.body)[0]

          if json
            data[url]['last_commit'] = {
              'author_date' => json['commit']['author']['date'],
              'committer_date' => json['commit']['committer']['date']
            }
          end
        else
          puts "Invalid response for #{response.uri}: #{response}"
        end

        if users[user].nil?
          response = Net::HTTP.get_response(URI("https://api.github.com/users/#{user}"), hh)

          if response.code.to_i == 200
            json = JSON.parse(response.body)
            users[user] = json
          else
            puts "Invalid response for #{response.uri}: #{response}"
          end
        end

        data[url]['user_name'] = users[user] && users[user]['name']
      else
        puts "Invalid response for #{response.uri}: #{response}"
      end
    else
      puts "Skipping #{url}"
    end
  end

  File.write(File.join(__dir__, '_data', 'github_info.yml'), YAML.dump(data))
end
