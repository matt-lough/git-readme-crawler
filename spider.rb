require 'rest-client'
require 'json'
require 'httparty'
require 'hunspell'

# Dictionary list https://cgit.freedesktop.org/libreoffice/dictionaries/tree/en

API_URL = 'https://api.github.com'

def git_url_to_gitraw_url(url)
  url.sub('github.com', 'raw.githubusercontent.com')
end

def is_404?(url)
  response = HTTParty.get(url)
  response.code == 404
end

def ignore_word?(word)
  git_words = ['git', 'blob', 'master', 'github', 'init', 'repo']
  dev_words = [
    'bytecode', 'compiler', 'rails', 'cd', 'rubygems', 'http', 'https',
    'md', 'dir', 'txt', 'config', 'mysql', 'rb', 'rss', 'dev', 'activerecord',
    'js', 'html', 'jpg', 'backend', 'mimetype', 'auth', 'www', 'png',
    'travis', 'svg', 'ci', 'jit', 'mpl', 'llvm', 'http', 'url', 'mkdir'
  ]
  dev_symbols = ['::', '.', '--', '#', '=>', '`', '_', '&', '*' ]
  # Word should be ignored if it contains one of these subsets
  word_subs = ['Controller', 'Exception', 'Action']

  return true if git_words.include? word
  return true if dev_words.include? word
  dev_symbols.each do |symbol|
    return true if word.include? symbol
  end
  word_subs.each do |symbol|
    return true if word.include? symbol
  end
  false
end

# Returns first valid Readme URL or nil
def find_readme_url(repo_url)
  html_url = git_url_to_gitraw_url(repo_url)
  file_names = ['README.md', 'README.MD', 'readme.md', 'readme.MD', 'README', 'readme']
  existing_files = file_names.select {|file| !is_404?(html_url + '/master/' + file) }
  if !existing_files.empty?
    return html_url + '/master/' + existing_files.first
  end
  nil
end

def get_words_from_readme(readme)
  readme = readme.gsub(/[^\w]/, ' ')
  readme.split(' ')
end

def spellcheck_repo(repo)
  p "Repo Name: #{repo['name']}"
  p "Repo URL: #{repo['html_url']}"

  readme_url = find_readme_url(repo['html_url'])

  if readme_url.nil?
    p "Could not find readme"
    return nil
  end

  p "Found Readme file: #{readme_url}"
  response = HTTParty.get(readme_url)

  sp = Hunspell.new('en_US-custom.aff', 'en_US-custom.dic')
  readme_words = get_words_from_readme(response.body)
  invalid_words = []
  words_seen = {}
  readme_words.each do |word|
    word = word.downcase
    next if ignore_word?(word)
    next if word == repo['name'].downcase
    if !sp.spellcheck(word) and !sp.suggest(word).empty? and !words_seen.key?(word)
      words_seen[word] = true
      invalid_words.push(word)
    end
  end
  p "Mispelled words #{invalid_words.size}"
  p invalid_words
end

def get_public_repos_page(next_link='')
  if next_link == ''
    response = RestClient.get(API_URL+'/repositories')
  else
    response = RestClient.get(next_link)
  end
  next_link = response.headers[:link].split(';')[0].tr('<', '').tr('>', '')
  repos = JSON.parse(response)
  return {'repos' => repos, 'next_link' => next_link}
end

def main
  p "How many pages would you like? (1-10)"
  inp = gets
  repos = []
  next_link = ''
  if (1..10).include? inp.to_i
    (1..inp.to_i).to_a.each do |page_num|
      get_page = get_public_repos_page(next_link)
      repos += get_page['repos']
      next_link = get_page['next_link']
    end
  end

  repo_num = 0
  while 1
    p "Repo number? (0-#{repos.size})"
    inp = gets
    if (0..repos.size).include? inp.to_i
      spellcheck_repo(repos[inp.to_i])
    else
      spellcheck_repo(repos[repo_num])
      repo_num += 1
      p repo_num
    end
  end

end

main
