lwAddDevice("R-DC", 0, "2911", 460, 60);
lwAddDevice("R-JKT", 0, "2911", 160, 200);
lwAddDevice("R-BDG", 0, "2911", 460, 340);
lwAddDevice("R-SBY", 0, "2911", 760, 200);
lwAddDevice("SW-DC", 1, "2960-24TT", 460, -80);
lwAddDevice("SRV-APP", 9, "Server-PT", 340, -220);
lwAddDevice("SRV-DB", 9, "Server-PT", 460, -220);
lwAddDevice("SRV-BACKUP", 9, "Server-PT", 580, -220);
lwAddDevice("PC-NOC-1", 8, "PC-PT", 680, -80);
lwAddDevice("PC-NOC-2", 8, "PC-PT", 760, -80);
lwAddDevice("SW-JKT", 1, "2960-24TT", 60, 340);
lwAddDevice("PC-JKT-1", 8, "PC-PT", -40, 470);
lwAddDevice("PC-JKT-2", 8, "PC-PT", 40, 470);
lwAddDevice("PC-JKT-3", 8, "PC-PT", 120, 470);
lwAddDevice("SW-BDG", 1, "2960-24TT", 460, 480);
lwAddDevice("PC-BDG-1", 8, "PC-PT", 360, 610);
lwAddDevice("PC-BDG-2", 8, "PC-PT", 440, 610);
lwAddDevice("PC-BDG-3", 8, "PC-PT", 520, 610);
lwAddDevice("SW-SBY", 1, "2960-24TT", 860, 340);
lwAddDevice("PC-SBY-1", 8, "PC-PT", 800, 470);
lwAddDevice("PC-SBY-2", 8, "PC-PT", 880, 470);
lwAddDevice("PC-SBY-3", 8, "PC-PT", 960, 470);
lwAddLink("R-DC", "GigabitEthernet0/0", "R-JKT", "GigabitEthernet0/0", 8101);
lwAddLink("R-JKT", "GigabitEthernet0/1", "R-BDG", "GigabitEthernet0/0", 8101);
lwAddLink("R-BDG", "GigabitEthernet0/1", "R-SBY", "GigabitEthernet0/0", 8101);
lwAddLink("R-SBY", "GigabitEthernet0/2", "R-DC", "GigabitEthernet0/2", 8101);
lwAddLink("R-DC", "GigabitEthernet0/1", "SW-DC", "GigabitEthernet0/1", 8100);
lwAddLink("R-JKT", "GigabitEthernet0/2", "SW-JKT", "GigabitEthernet0/1", 8100);
lwAddLink("R-BDG", "GigabitEthernet0/2", "SW-BDG", "GigabitEthernet0/1", 8100);
lwAddLink("R-SBY", "GigabitEthernet0/1", "SW-SBY", "GigabitEthernet0/1", 8100);
lwAddLink("SW-DC", "FastEthernet0/1", "SRV-APP", "FastEthernet0", 8100);
lwAddLink("SW-DC", "FastEthernet0/2", "SRV-DB", "FastEthernet0", 8100);
lwAddLink("SW-DC", "FastEthernet0/3", "SRV-BACKUP", "FastEthernet0", 8100);
lwAddLink("SW-DC", "FastEthernet0/11", "PC-NOC-1", "FastEthernet0", 8100);
lwAddLink("SW-DC", "FastEthernet0/12", "PC-NOC-2", "FastEthernet0", 8100);
lwAddLink("SW-JKT", "FastEthernet0/1", "PC-JKT-1", "FastEthernet0", 8100);
lwAddLink("SW-JKT", "FastEthernet0/2", "PC-JKT-2", "FastEthernet0", 8100);
lwAddLink("SW-JKT", "FastEthernet0/3", "PC-JKT-3", "FastEthernet0", 8100);
lwAddLink("SW-BDG", "FastEthernet0/1", "PC-BDG-1", "FastEthernet0", 8100);
lwAddLink("SW-BDG", "FastEthernet0/2", "PC-BDG-2", "FastEthernet0", 8100);
lwAddLink("SW-BDG", "FastEthernet0/3", "PC-BDG-3", "FastEthernet0", 8100);
lwAddLink("SW-SBY", "FastEthernet0/1", "PC-SBY-1", "FastEthernet0", 8100);
lwAddLink("SW-SBY", "FastEthernet0/2", "PC-SBY-2", "FastEthernet0", 8100);
lwAddLink("SW-SBY", "FastEthernet0/3", "PC-SBY-3", "FastEthernet0", 8100);
/* === Configuraciones CLI por dispositivo ===
Copiar y pegar en la CLI de cada dispositivo. */
/* --- R-DC ---
enable
configure terminal
hostname R-DC
no ip domain-lookup

interface GigabitEthernet0/0
 ip address 10.0.0.1 255.255.255.252
 no shutdown
 exit

interface GigabitEthernet0/1
 ip address 192.168.0.1 255.255.255.0
 no shutdown
 exit

interface GigabitEthernet0/2
 ip address 10.0.0.14 255.255.255.252
 no shutdown
 exit

ip dhcp excluded-address 192.168.0.1 192.168.0.20
ip dhcp pool LAN_DC
 network 192.168.0.0 255.255.255.0
 default-router 192.168.0.1
 dns-server 192.168.0.6
 exit

router ospf 1
 router-id 10.0.0.1
 network 10.0.0.0 0.0.0.3 area 0
 network 10.0.0.12 0.0.0.3 area 0
 network 192.168.0.0 0.0.0.255 area 0
 exit

end
write memory
*/ 
/* --- R-JKT ---
enable
configure terminal
hostname R-JKT
no ip domain-lookup

interface GigabitEthernet0/0
 ip address 10.0.0.2 255.255.255.252
 no shutdown
 exit

interface GigabitEthernet0/1
 ip address 10.0.0.5 255.255.255.252
 no shutdown
 exit

interface GigabitEthernet0/2
 ip address 192.168.1.1 255.255.255.0
 no shutdown
 exit

ip dhcp excluded-address 192.168.1.1 192.168.1.9
ip dhcp pool LAN_JKT
 network 192.168.1.0 255.255.255.0
 default-router 192.168.1.1
 dns-server 192.168.0.6
 exit

router ospf 1
 router-id 10.0.0.2
 network 10.0.0.0 0.0.0.3 area 0
 network 10.0.0.4 0.0.0.3 area 0
 network 192.168.1.0 0.0.0.255 area 0
 exit

end
write memory
*/ 
/* --- R-BDG ---
enable
configure terminal
hostname R-BDG
no ip domain-lookup

interface GigabitEthernet0/0
 ip address 10.0.0.6 255.255.255.252
 no shutdown
 exit

interface GigabitEthernet0/1
 ip address 10.0.0.9 255.255.255.252
 no shutdown
 exit

interface GigabitEthernet0/2
 ip address 192.168.2.1 255.255.255.0
 no shutdown
 exit

ip dhcp excluded-address 192.168.2.1 192.168.2.9
ip dhcp pool LAN_BDG
 network 192.168.2.0 255.255.255.0
 default-router 192.168.2.1
 dns-server 192.168.0.6
 exit

router ospf 1
 router-id 10.0.0.6
 network 10.0.0.4 0.0.0.3 area 0
 network 10.0.0.8 0.0.0.3 area 0
 network 192.168.2.0 0.0.0.255 area 0
 exit

end
write memory
*/ 
/* --- R-SBY ---
enable
configure terminal
hostname R-SBY
no ip domain-lookup

interface GigabitEthernet0/0
 ip address 10.0.0.10 255.255.255.252
 no shutdown
 exit

interface GigabitEthernet0/1
 ip address 192.168.3.1 255.255.255.0
 no shutdown
 exit

interface GigabitEthernet0/2
 ip address 10.0.0.13 255.255.255.252
 no shutdown
 exit

ip dhcp excluded-address 192.168.3.1 192.168.3.9
ip dhcp pool LAN_SBY
 network 192.168.3.0 255.255.255.0
 default-router 192.168.3.1
 dns-server 192.168.0.6
 exit

router ospf 1
 router-id 10.0.0.10
 network 10.0.0.8 0.0.0.3 area 0
 network 10.0.0.12 0.0.0.3 area 0
 network 192.168.3.0 0.0.0.255 area 0
 exit

end
write memory
*/ 
/* --- SW-DC ---
enable
configure terminal
hostname SW-DC
end
write memory
*/ 
/* --- SW-JKT ---
enable
configure terminal
hostname SW-JKT
end
write memory
*/ 
/* --- SW-BDG ---
enable
configure terminal
hostname SW-BDG
end
write memory
*/ 
/* --- SW-SBY ---
enable
configure terminal
hostname SW-SBY
end
write memory
*/ 