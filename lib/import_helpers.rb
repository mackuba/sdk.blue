module ImportHelpers
  def normalize_repo_url(url)
    return nil if url.nil?

    url.gsub(%r{^.*://}, 'https://')
       .gsub(/\.git$/, '')
       .gsub(%r{tangled\.sh/}, 'tangled.org/')
       .gsub(%r{tangled\.org/@}, 'tangled.org/')
       .gsub(/\/$/, '')
  end
end
