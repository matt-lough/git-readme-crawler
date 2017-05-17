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
  git_words = ['git', 'blob', 'master', 'github', 'init', 'repo', 'Repo']
  dev_words = [
    'bytecode', 'compiler', 'Rails', 'cd', 'RubyGems', 'http', 'https',
    'md', 'dir', 'txt', 'config', 'mysql', 'rb', 'rss', 'dev', 'ActiveRecord',
    'js', 'rubygems', 'html', 'jpg', 'backend', 'mimetype', 'auth', 'www',
    'travis', 'svg', 'ci', 'JIT', 'MPL', 'LLVM'
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
  readme = readme.gsub(/[^\w']/, ' ')
  readme.split(' ')
end

def main
  sp = Hunspell.new('en_US.aff', 'en_US.dic')

  response = RestClient.get(API_URL+'/repositories')
  repos = JSON.parse(response)

  killcount = 0
  repos.each do |repo|
    if killcount > 15
      abort("DONE")
    end
    killcount += 1

    p "Repo Name: #{repo['name']}"
    p "Repo URL: #{repo['html_url']}"

    readme_url = find_readme_url(repo['html_url'])

    if readme_url.nil?
      p "Could not find readme"
      next
    end
    p "Found Readme file: #{readme_url}"
    response = HTTParty.get(readme_url)

    readme_words = get_words_from_readme(response.body)
    invalid_words = []
    readme_words.each do |word|
      next if ignore_word?(word)
      next if word.downcase == repo['name'].downcase
      invalid_words.push(word) if !sp.spellcheck(word)
    end
    p invalid_words
  end
end

main
