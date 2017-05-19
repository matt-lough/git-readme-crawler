require 'rest-client'
require 'json'
require 'httparty'
require 'ffi/hunspell'
require 'cli'

# Dictionary list https://cgit.freedesktop.org/libreoffice/dictionaries/tree/en

API_URL = 'https://api.github.com'
MINIMUM_WORD_SIZE = 4
DEV_DICT = FFI::Hunspell.dict('en_US-dev')
DICT = FFI::Hunspell.dict('en_US')

def git_url_to_gitraw_url(url)
  url.sub('github.com', 'raw.githubusercontent.com')
end

def is_404?(url)
  response = HTTParty.get(url)
  response.code == 404
end

def ignore_word?(word)
  dev_symbols = ['::', '.', '--', '#', '=>', '`', '_', '&', '*' ]
  # Word should be ignored if it contains one of these subsets
  word_subs = ['Controller', 'Exception', 'Action']

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

def get_readme_text(repo_url)
  readme_url = find_readme_url(repo_url)

  if readme_url.nil?
    p "Could not find readme"
    return nil
  end

  p "Found Readme file: #{readme_url}"
  response = HTTParty.get(readme_url)
  response.body
end

def spellcheck_repo(repo)
  p "Repo Name: #{repo['name']}"
  p "Repo URL: #{repo['html_url']}"

  readme_text = get_readme_text(repo['html_url'])
  return nil if readme_text.nil?

  readme_words = get_words_from_readme(readme_text)

  invalid_words = []
  words_seen = {}

  readme_words.each do |word|
    word = word.downcase
    next if word.size < MINIMUM_WORD_SIZE
    next if ignore_word?(word)
    next if word == repo['name'].downcase
    if !DICT.check?(word) and !DEV_DICT.check?(word) and !words_seen.key?(word)
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

def get_repos
  p "How many pages would you like? (1-10)"
  inp = STDIN.gets
  repos = []
  next_link = ''
  if (1..10).include? inp.to_i
    (1..inp.to_i).to_a.each do |page_num|
      get_page = get_public_repos_page(next_link)
      repos += get_page['repos']
      next_link = get_page['next_link']
    end
  end
  repos
end

def spellcheck_repos(repos_ary)
  while 1
    p "Repo number? (0-#{repos_ary.size})"
    inp = STDIN.gets
    if (0..repos_ary.size).include? inp.to_i
      spellcheck_repo(repos_ary[inp.to_i])
    end
  end
end

def add_word_to_devdict(word)
  dict_path = File.join(Gem.user_home,'Library/Spelling/')
  f = open(dict_path + 'en_US-dev.dic', 'r+')
  f_ary = f.readlines
  if f_ary.include? word + "\n"
    f.close
    return nil
  end
  f.rewind
  f_content = f.read
  num_words = f_ary[0].strip
  new_f = f_content.sub(/^\d+/, (num_words.to_i + 1).to_s) + word + "\n"
  f.rewind
  f.write(new_f)
  f.close
end

def learn_repos(repos_ary)
  repos_ary.each do |repo|
    readme_text = get_readme_text(repo['html_url'])
    next if readme_text.nil?
    readme_words = get_words_from_readme(readme_text)
    readme_words.uniq.each do |word|
      word = word.downcase
      next if word.size < MINIMUM_WORD_SIZE
      next if word == repo['name'].downcase
      next if ignore_word?(word)
      if !DEV_DICT.check?(word) and !DICT.check?(word)
        p "Add this word to dictionary? #{word} (y/n)"
        inp = STDIN.gets
        add_word_to_devdict(word) if inp == "y\n"
      end
    end
  end
end

settings = CLI.new do
  switch :learn, :description => 'learning mode'
end.parse!

repos = get_repos

if settings.learn
  learn_repos(repos)
else
  spellcheck_repos(repos)
end
