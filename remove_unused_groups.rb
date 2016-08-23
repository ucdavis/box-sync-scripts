require 'csv'
require 'boxr'
require 'yaml'

# Load needed API OAuth2 settings from credentials.yml
$CONFIG = YAML.load_file('credentials.yml')

ACCESS_TOKEN = $CONFIG['ACCESS_TOKEN']
REFRESH_TOKEN = $CONFIG['REFRESH_TOKEN']
CLIENT_ID = $CONFIG['CLIENT_ID']
CLIENT_SECRET = $CONFIG['CLIENT_SECRET']

# Set up the 'Boxr' Box.com API client
token_refresh_callback = lambda{ |access, refresh, identifier| puts "NEW ACCESS: #{access}, NEW REFRESH: #{refresh}" }
client = Boxr::Client.new(ACCESS_TOKEN,
                          refresh_token: REFRESH_TOKEN,
                          client_id: CLIENT_ID,
                          client_secret: CLIENT_SECRET,
                          &token_refresh_callback)

# Fetch all automated groups.
groups = client.groups

total_groups = groups.length

# Assume any group ending in "-S16" is an automated group.
# TODO: Make this much smarter.
groups = groups.select{ |g| g.name.end_with? "-S16" }

puts "There are #{groups.length} automated groups out of #{total_groups} total groups."

# Scan for unused groups
empty_groups = []
groups.each do |g|
  if client.group_collaborations(g).length == 0
    empty_groups << g
  end
end

puts "There are #{empty_groups.length} automated groups with no collaborations (files or folders) out of #{total_groups} total groups. Deleting ..."

# Delete all groups in 'empty_groups'
empty_groups.each do |eg|
  begin
    client.delete_group(eg)
  rescue Boxr::BoxrError => e
    puts "Encountered exception while deleting group #{eg.name} ..."
    puts e
    puts "Continuing ..."
  end
end
