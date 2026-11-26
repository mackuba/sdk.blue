module ImportHelpers
  def normalize_repo_url(url)
    return nil if url.nil?

    url.gsub(%r{^.*://}, 'https://')
       .gsub(/\.git$/, '')
       .gsub(%r{tangled\.sh/}, 'tangled.org/')
       .gsub(%r{tangled\.org/@}, 'tangled.org/')
       .gsub(/\/$/, '')
  end

  def package_matches_repo?(package, repo_urls)
    [package.repository_url, package.homepage_url].any? { |url| repo_urls.include?(normalize_repo_url(url)) }
  end
end
