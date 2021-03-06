require 'csv'
require 'boxr'
require 'yaml'

# Check for command line arguments
if ARGV.length != 1
  puts "Usage: ruby ./make_students_in_groups.rb filename.csv"
  exit(0)
end

# First argument should be CSV file
csv_filename = ARGV[0]

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

# Fetch all users. This saves a lot of web requests.
users = []
offset = 0
page_size = 1000

# Ruby's silly version of a do..while loop ...
loop do
  user_set = client.all_users(offset: offset, limit: page_size)
  
  offset = offset + page_size

  break if (user_set.length == 0)
  
  users << user_set
end

users = users.flatten

puts "Number of users at start:"
puts users.length


# Fetch all groups. This also saves a lot of web requests.
groups = []
groups = client.groups

puts "Number of groups at start:"
puts groups.length

# Read the CSV file
# "COURSE_ID","CRN","NAME","EMAIL"
csv_data = CSV.read(csv_filename)

# Poor man's progress bar being set up here.
row = 1
total_rows = csv_data.length

# For each row in the CSV file ...
csv_data.each do |csv|
  puts "#{Time.now.to_s}: #{row} of #{total_rows} ..."

  # Extract the necessary columns. Note we cut off a term code (e.g. 201610) and add "S16"
  group_name = (csv[0][0..-7] + "S16").upcase
  crn = csv[1]
  name = csv[2]
  email = csv[3]
  
  # Find or create the group ...
  g = groups.select{|g| g.name.upcase == group_name}
  if g == []
    puts "Creating #{group_name} ..."
    g = client.create_group(group_name)
    groups << g
  else
    puts "Using existing #{group_name} ..."
    g = g[0]
  end
  
  puts "\tGroup ID: #{g.id}"

  # Find or create the student ...
  u = users.select{|u| u.login.downcase == email}
  if u == []
    puts "\tCreating #{email} ..."
  
    begin
      u = client.create_user(name, login: email)
      users << u
    rescue Boxr::BoxrError => e
      if e.status == 409
        puts "\tUser already exists, cannot create. Searching ..."
        u = client.all_users(filter_term: email)
        if u != []
          puts "\t\tfound."
          u = u[0]
        else
          puts "\tERROR: API claims user exists but could not be found (#{email})."
        end
      else
        puts "\tERROR: Unknown error while creating user!"
        puts e
      end
    end
  else
    puts "\tUsing existing #{email} ..."
    u = u[0]
  end

  # Add student as a 'member' of group (not an 'admin')
  puts "\tAdding user to group ..."
  begin
    client.add_user_to_group(u, g)
    puts "\tDone!"
  rescue Boxr::BoxrError => e
    if e.status == 409
      puts "\tUser already in group."
    else
      puts "\tERROR: Unknown error while adding user to group."
      puts e
    end
  end
  
  # Poor man's progress bar just churnin' away here
  row = row + 1
end
