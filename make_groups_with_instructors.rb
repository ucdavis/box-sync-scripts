require 'csv'
require 'boxr'
require 'yaml'

if ARGV.length != 1
  puts "Usage: ruby ./make_groups_with_instructors.rb filename.csv"
  exit(0)
end

csv_filename = ARGV[0]

$CONFIG = YAML.load_file('credentials.yml')

ACCESS_TOKEN = $CONFIG['ACCESS_TOKEN']
REFRESH_TOKEN = $CONFIG['REFRESH_TOKEN']
CLIENT_ID = $CONFIG['CLIENT_ID']
CLIENT_SECRET = $CONFIG['CLIENT_SECRET']

token_refresh_callback = lambda{ |access, refresh, identifier| puts "NEW ACCESS: #{access}, NEW REFRESH: #{refresh}" }
client = Boxr::Client.new(ACCESS_TOKEN,
                          refresh_token: REFRESH_TOKEN,
                          client_id: CLIENT_ID,
                          client_secret: CLIENT_SECRET,
                          &token_refresh_callback)

users = []
offset = 0
page_size = 1000

# Fetch all users
loop do
  user_set = client.all_users(offset: offset, limit: page_size)
  
  offset = offset + page_size

  break if (user_set.length == 0)
  
  users << user_set
end

users = users.flatten

puts "Number of users at start:"
puts users.length

groups = []

# Fetch all groups
groups = client.groups

puts "Number of groups at start:"
puts groups.length

# Read the CSV file
# ["FACULTY_NAME", "FACULTY_EMAIL", "COURSE", "CRN"]
csv_data = CSV.read(csv_filename)

# '-s16' for the term
csv_data.each do |csv|
  name = csv[0]
  email = csv[1].downcase
  group_name_data = csv[2].split(" ")
  crn = csv[3]

  # Make the groups (all uppercase), get group ID  
  group_name = (group_name_data[0] + group_name_data[1] + "-" + group_name_data[2] + "-S16").upcase

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

  # Does the instructor already exist?
  u = users.select{|u| u.login.downcase == email}
  if u == []
    puts "\tCreating #{email} ..."
  
    begin
      u = client.create_user(name, login: email)
      users << u
    rescue Boxr::BoxrError => e
      if e.status == 409
        puts "\tUser already exists, cannot create."
      else
        puts "\tERROR: Unknown error while creating user!"
        puts e
      end
    end
  else
    puts "\tUsing existing #{email} ..."
    u = u[0]
  end

  # Add instructor as a 'member', not as an 'admin'
  puts "\tAdding user to group ..."
  begin
    client.add_user_to_group(u, g)
    puts "\tDone!"
  rescue Boxr::BoxrError => e
    if e.status == 409
      puts "\tUser already in group."
    else
      puts "\tERROR: Unknown error while adding user to group."
    end
  end
end
