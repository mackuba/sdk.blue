require 'didkit'

module ImportHelpers
  def normalize_repo_url(url)
    return nil if url.nil?

    url = url.gsub(%r{^.*://}, 'https://')
             .gsub(/\.git$/, '')
             .gsub(%r{tangled\.sh/}, 'tangled.org/')
             .gsub(%r{tangled\.org/@}, 'tangled.org/')
             .gsub(/\/$/, '')

    if url =~ /tangled\.org/
      handle = url.split('/')[3]

      if did = resolve_handle(handle)
        url = url.gsub(handle, did)
      end
    end

    url
  end

  def package_matches_repo?(package, repo_urls)
    [package.repository_url, package.homepage_url].any? { |url| repo_urls.include?(normalize_repo_url(url)) }
  end

  def resolve_handle(handle)
    @handle_cache ||= {}

    return @handle_cache[handle] if @handle_cache.key?(handle)

    @handle_cache[handle] = DID.resolve_handle(handle)&.to_s
  end
end
