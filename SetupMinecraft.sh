#!/bin/bash
# Minecraft Server Installation Script - James A. Chambers - https://www.jamesachambers.com
# GitHub Repository: https://github.com/TheRemote/RaspberryPiMinecraft
echo "Minecraft Server installation script by James Chambers - March 2nd 2019"
echo "Latest version always at https://github.com/TheRemote/RaspberryPiMinecraft"
echo "Don't forget to set up port forwarding on your router!  The default port is 25565"

# Install screen to run minecraft in the background
echo "Installing screen, sudo, net-tools..."
apt-get update && apt-get install sudo -y
sudo apt-get update
sudo apt-get install screen net-tools -y

# Check to see if Minecraft directory already exists, if it does then exit
if [ -d "minecraft" ]; then
  echo "Directory minecraft already exists!  Updating scripts and configuring service ..."

  # Get Home directory path and username
  cd minecraft
  DirName=$(readlink -e ~)
  UserName=$(whoami)

  # Ask user for amount of memory they want to dedicate to the Minecraft server
  echo "Getting total system memory..."
  sync
  sleep 0.1s
  TotalMemory=$(awk '/MemTotal/ { printf "%.0f \n", $2/1024 }' /proc/meminfo)
  AvailableMemory=$(awk '/MemAvailable/ { printf "%.0f \n", $2/1024 }' /proc/meminfo)
  RecommendedMemory=$(echo $AvailableMemory-$AvailableMemory*0.08/1 | bc)
  echo "Total memory: $TotalMemory - Available Memory: $AvailableMemory"
  echo "Please enter the amount of memory you want to dedicate to the server.  A minimum of 700MB is recommended."
  echo "You must leave enough left over memory for the operating system to run background processes."
  echo "If all memory is exhausted the Minecraft server will either crash or force background processes into the paging file (very slow)."
  MemSelected=0
  while [[ $MemSelected -lt 600 || $MemSelected -ge $TotalMemory ]]; do
    read -p "Enter amount of memory in megabytes to dedicate to the Minecraft server (recommended: $RecommendedMemory): " MemSelected
    MemSelected=$(echo $MemSelected | bc)
    if [[ $MemSelected -lt 600 ]]; then
      echo "Please enter a minimum of 600"
    elif [[ $MemSelected -gt $TotalMemory ]]; then
      echo "Please enter an amount less than the total memory in the system ($TotalMemory)"
    fi
  done
  echo "Amount of memory for Minecraft server selected: $MemSelected MB"

  # Remove existing scripts
  rm minecraft/start.sh minecraft/stop.sh minecraft/restart.sh

  # Download start.sh from repository
  echo "Grabbing start.sh from repository..."
  wget -O start.sh https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/start.sh
  chmod +x start.sh
  sed -i "s:dirname:$DirName:g" start.sh
  sed -i "s:memselect:$MemSelected:g" start.sh

  # Download stop.sh from repository
  echo "Grabbing stop.sh from repository..."
  wget -O stop.sh https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/stop.sh
  chmod +x stop.sh
  sed -i "s:dirname:$DirName:g" stop.sh

  # Download restart.sh from repository
  echo "Grabbing restart.sh from repository..."
  wget -O restart.sh https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/restart.sh
  chmod +x restart.sh
  sed -i "s:dirname:$DirName:g" restart.sh

  # Service configuration
  sudo rm /etc/systemd/system/minecraft.service
  sudo wget -O /etc/systemd/system/minecraft.service https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/minecraft.service
  sudo chmod +x /etc/systemd/system/minecraft.service
  sudo sed -i "s/replace/$UserName/g" /etc/systemd/system/minecraft.service
  sudo sed -i "s:dirname:$DirName:g" /etc/systemd/system/minecraft.service
  sudo systemctl daemon-reload
  echo -n "Start Minecraft server at startup automatically (y/n)?"
  read answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    sudo systemctl enable minecraft.service

    # Automatic reboot at 4am configuration
    echo -n "Automatically reboot Pi and update server at 4am daily (y/n)?"
    read answer
    if [ "$answer" != "${answer#[Yy]}" ]; then
      croncmd="$DirName/minecraft/restart.sh"
      cronjob="0 4 * * * $croncmd"
      ( crontab -l | grep -v -F "$croncmd" ; echo "$cronjob" ) | crontab -
      echo "Daily reboot scheduled.  To change time or remove automatic reboot type crontab -e"
    fi
  fi

  echo "Minecraft installation scripts have been updated to the latest version!"
  exit 0
fi

# Get total system memory and make sure we are a 1024MB or higher board
echo "Getting total system memory..."
TotalMemory=$(awk '/MemTotal/ { printf "%.0f \n", $2/1024 }' /proc/meminfo)
AvailableMemory=$(awk '/MemAvailable/ { printf "%.0f \n", $2/1024 }' /proc/meminfo)
echo "Total memory: $TotalMemory - Available Memory: $AvailableMemory"
if [ $TotalMemory -lt 700 ]; then
  echo "Not enough memory to run a Minecraft server.  Requires Raspberry Pi with at least 1024MB of memory!"
  exit 1
fi

# Check system architecture to ensure we are running ARMv7
echo "Getting system CPU architecture..."
CPUArch=$(uname -m)
echo "System Architecture: $CPUArch"
if [[ "$CPUArch" == *"aarch"* || "$CPUArch" == *"arm"* ]]; then
  echo "Installing latest Java OpenJDK..."
  JavaVer=$(apt-cache show openjdk-11-jre-headless | grep Version | awk 'NR==1{ print $2 }')
  if [[ "$JavaVer" ]]; then
    sudo apt-get install openjdk-11-jre-headless -y
  else
    sudo apt-get install openjdk-9-jre-headless -y
    # Create soft link to fix broken ca-certificates-java package that looks for client instead of server
    if [[ "$CPUArch" == *"armv7"* || "$CPUArch" == *"armhf"* ]]; then
      sudo ln -s /usr/lib/jvm/java-9-openjdk-armhf/lib/server /usr/lib/jvm/java-9-openjdk-armhf/lib/client
    elif [[ "$CPUArch" == *"aarch64"* || "$CPUArch" == *"arm64"* ]]; then
      sudo ln -s /usr/lib/jvm/java-9-openjdk-arm64/lib/server /usr/lib/jvm/java-9-openjdk-arm64/lib/client
    fi
    sudo apt-get install openjdk-9-jre-headless -y
  fi

  # Check if Java installation was successful
  if [ -n "`which java`" ]; then
    echo "Java installed successfully"
  else
    echo "Java did not install successfully -- please check the above output to see what went wrong."
    exit 1
  fi
else
  echo "You must be using a Raspberry Pi with ARMv7 support to run a Minecraft server!"
  echo "ARMv7 enables the G1GC garbage collector in Java which is required to have playable performance."
  exit 1
fi

# Check if we are running Raspbian for the overclock and split GPU memory configuration.  If vcgencmd is not present then skip.
if [ -n "`which vcgencmd`" ]; then
  RebootRequired=0
  # Check MicroSD clock speed
  MicroSDClock="$(sudo grep "actual clock" /sys/kernel/debug/mmc0/ios 2>/dev/null | awk '{printf("%0.3f MHz", $3/1000000)}')"
  if [ -n "$MicroSDClock" ]; then
    echo "MicroSD clock: $MicroSDClock"
    if [ "$MicroSDClock" != "100.000 MHz" ]; then
      echo "Your MicroSD clock is set at $MicroSDClock instead of the recommended 100 MHz"
      echo "This setup can overclock this for you but some (usually cheaper) MicroSD cards will not boot with this setting"
      echo "If this happens you can remove dtparam=sd_overclock=100 or reimage the MicroSD and the Pi will work normally again"
      echo "This is at your own risk and does make a huge performance difference.  If you have a card that won't overclock or don't want to do this press n."
      echo -n "Set clock speed to 100 MHz?  Requires reboot. (y/n)?"
      read answer

      if [ "$answer" != "${answer#[Yy]}" ]; then
          sudo bash -c 'printf "dtparam=sd_overclock=100\n" >> /boot/config.txt'
          echo "SD Card speed has been changed.  Please run setup again after reboot."
          RebootRequired=1
      fi
    fi
  fi

  # Check that GPU Shared memory is set to 16MB to give our server more resources
  echo "Getting shared GPU memory..."
  GPUMemory=$(vcgencmd get_mem gpu)
  echo "Memory being used by shared GPU: $GPUMemory"
  if [ "$GPUMemory" != "gpu=16M" ]; then
    echo "GPU memory needs to be set to 16MB for best performance."
    echo "This can be set in sudo raspi-config or the script can change it for you now."
    echo -n "Change GPU shared memory to 16MB?  Requires reboot. (y/n)?"
    read answer

    if [ "$answer" != "${answer#[Yy]}" ]; then
        sudo raspi-config nonint do_memory_split "16"
        echo "Split GPU memory has been changed.  Please run setup again after reboot."
        RebootRequired=1
    fi
  fi

  # Check if any configuration changes needed a reboot
  if [ $RebootRequired -eq 1 ]; then
    echo "System is restarting -- please run setup again after restart"
    sudo reboot
    exit 0
  fi
fi

# Calculate amount of recommended memory leaving enough room for the OS processes to run
sync
sleep 0.1s
AvailableMemory=$(awk '/MemAvailable/ { printf "%.0f \n", $2/1024 }' /proc/meminfo)
RecommendedMemory=$(echo $AvailableMemory-$AvailableMemory*0.08/1 | bc)
if [ $RecommendedMemory -lt 700 ]; then
  echo "WARNING:  Available memory to run the server is less than 700MB.  This will impact performance and stability."
  echo "You can increase available memory by closing other processes.  If nothing else is running your distro may be using all available memory."
  echo "It is recommended to use a headless distro like Raspbian Lite to ensure you have the maximum memory available possible."
  read -n1 -r -p "Press any key to continue"
fi

# Ask user for amount of memory they want to dedicate to the Minecraft server
echo "Please enter the amount of memory you want to dedicate to the server.  A minimum of 700MB is recommended."
echo "You must leave enough left over memory for the operating system to run background processes."
echo "If all memory is exhausted the Minecraft server will either crash or force background processes into the paging file (very slow)."
MemSelected=0
while [[ $MemSelected -lt 600 || $MemSelected -ge $TotalMemory ]]; do
  read -p "Enter amount of memory in megabytes to dedicate to the Minecraft server (recommended: $RecommendedMemory): " MemSelected
  MemSelected=$(echo $MemSelected | bc)
  if [[ $MemSelected -lt 600 ]]; then
    echo "Please enter a minimum of 600"
  elif [[ $MemSelected -gt $TotalMemory ]]; then
    echo "Please enter an amount less than the total memory in the system ($TotalMemory)"
  fi
done
echo "Amount of memory for Minecraft server selected: $MemSelected MB"

# Create server directory
echo "Creating minecraft server directory..."
cd ~
mkdir minecraft
cd minecraft
mkdir backups

# Get Home directory path and username
DirName=$(readlink -e ~)
UserName=$(whoami)

# Retrieve latest build of Paper minecraft server
echo "Getting latest Paper Minecraft server..."
wget -O paperclip.jar https://papermc.io/ci/job/Paper-1.13/lastSuccessfulBuild/artifact/paperclip.jar

# Run the Minecraft server for the first time which will build the modified server and exit saying the EULA needs to be accepted
echo "Building the Minecraft server..."
java -jar "-Xms$RecommendedMemory"M "-Xmx$RecommendedMemory"M paperclip.jar

# Accept the EULA
echo "Accepting the EULA..."
echo eula=true > eula.txt

# Download start.sh from repository
echo "Grabbing start.sh from repository..."
wget -O start.sh https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/start.sh
chmod +x start.sh
sed -i "s:dirname:$DirName:g" start.sh
sed -i "s:memselect:$MemSelected:g" start.sh

# Download stop.sh from repository
echo "Grabbing stop.sh from repository..."
wget -O stop.sh https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/stop.sh
chmod +x stop.sh
sed -i "s:dirname:$DirName:g" stop.sh

# Download restart.sh from repository
echo "Grabbing restart.sh from repository..."
wget -O restart.sh https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/restart.sh
chmod +x restart.sh
sed -i "s:dirname:$DirName:g" restart.sh

# Server configuration
echo "Enter a name for your server..."
read -p 'Server Name: ' servername
echo "server-name=$servername" >> server.properties
echo "motd=$servername" >> server.properties

# Service configuration
sudo wget -O /etc/systemd/system/minecraft.service https://raw.githubusercontent.com/TheRemote/RaspberryPiMinecraft/master/minecraft.service
sudo chmod +x /etc/systemd/system/minecraft.service
sudo sed -i "s/replace/$UserName/g" /etc/systemd/system/minecraft.service
sudo sed -i "s:dirname:$DirName:g" /etc/systemd/system/minecraft.service
sudo systemctl daemon-reload
echo -n "Start Minecraft server at startup automatically (y/n)?"
read answer
if [ "$answer" != "${answer#[Yy]}" ]; then
  sudo systemctl enable minecraft.service

  # Automatic reboot at 4am configuration
  TimeZone=$(cat /etc/timezone)
  CurrentTime=$(date)
  echo "Your time zone is currently set to $TimeZone.  Current system time: $CurrentTime"
  echo "You can adjust/remove the selected reboot time later by typing crontab -e"
  echo -n "Automatically reboot Pi and update server at 4am daily (y/n)?"
  read answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    croncmd="$DirName/minecraft/restart.sh"
    cronjob="0 4 * * * $croncmd"
    ( crontab -l | grep -v -F "$croncmd" ; echo "$cronjob" ) | crontab -
    echo "Daily reboot scheduled.  To change time or remove automatic reboot type crontab -e"
  fi
fi

# Finished!
echo "Setup is complete.  Starting Minecraft server..."
sudo systemctl start minecraft.service

# Sleep for 5 seconds to give the server time to start
sleep 5

screen -r minecraft
