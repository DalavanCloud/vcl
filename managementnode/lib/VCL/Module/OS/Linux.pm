#!/usr/bin/perl -w
###############################################################################
# $Id$
###############################################################################
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

=head1 NAME

VCL::Module::OS::Linux.pm - VCL module to support Linux operating systems

=head1 SYNOPSIS

 Needs to be written

=head1 DESCRIPTION

 This module provides VCL support for Linux operating systems.

=cut

##############################################################################
package VCL::Module::OS::Linux;

# Specify the lib path using FindBin
use FindBin;
use lib "$FindBin::Bin/../../..";

# Configure inheritance
use base qw(VCL::Module::OS);

# Specify the version of this module
our $VERSION = '2.00';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;

use VCL::utils;

##############################################################################

=head1 CLASS VARIABLES

=cut

=head2 $NODE_CONFIGURATION_DIRECTORY

 Data type   : String
 Description : Location on computer on which an image has been loaded where
               configuration files reside.

=cut

our $NODE_CONFIGURATION_DIRECTORY = '/root/VCL';

#/////////////////////////////////////////////////////////////////////////////

=head2 get_node_configuration_directory

 Parameters  : None.
 Returns     : String containing filesystem path
 Description : Retrieves the $NODE_CONFIGURATION_DIRECTORY variable value the
               OS. This is the path on the computer's hard drive where image
					configuration files and scripts are copied.

=cut

sub get_node_configuration_directory {
	return $NODE_CONFIGURATION_DIRECTORY;
}

##############################################################################

=head1 OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 pre_capture

 Parameters  :
 Returns     :
 Description :

=cut

sub pre_capture {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	my $request_id               = $self->data->get_request_id();
	my $reservation_id           = $self->data->get_reservation_id();
	my $image_id                 = $self->data->get_image_id();
	my $image_os_name            = $self->data->get_image_os_name();
	my $management_node_keys     = $self->data->get_management_node_keys();
	my $image_os_type            = $self->data->get_image_os_type();
	my $image_name               = $self->data->get_image_name();
	my $computer_id              = $self->data->get_computer_id();
	my $computer_short_name      = $self->data->get_computer_short_name();
	my $computer_node_name       = $self->data->get_computer_node_name();
	my $computer_type            = $self->data->get_computer_type();
	my $user_id                  = $self->data->get_user_id();
	my $user_unityid             = $self->data->get_user_login_id();
	my $managementnode_shortname = $self->data->get_management_node_short_name();
	my $computer_private_ip      = $self->data->get_computer_private_ip_address();

	notify($ERRORS{'OK'}, 0, "beginning Linux-specific image capture preparation tasks: $image_name on $computer_short_name");

	my @sshcmd;

	# Force user off computer 
	if ($self->logoff_user()){
		notify($ERRORS{'OK'}, 0, "forced $user_unityid off $computer_node_name");
	}

	# Remove user and clean external ssh file
	if ($self->delete_user()) {
		notify($ERRORS{'OK'}, 0, "$user_unityid deleted from $computer_node_name");
	}

	# try to clear /tmp
	if (run_ssh_command($computer_node_name, $management_node_keys, "/usr/sbin/tmpwatch -f 0 /tmp; /bin/cp /dev/null /var/log/wtmp", "root")) {
		notify($ERRORS{'DEBUG'}, 0, "cleartmp precapture $computer_node_name ");
	}

	#Clear ssh idenity keys from /root/.ssh 
	if (!$self->clear_private_keys()) {
		notify($ERRORS{'WARNING'}, 0, "unable to clear known identity keys");
	}

	if ($IPCONFIGURATION eq "static") {
		#so we don't have conflicts we should set the public adapter back to dhcp
		# reset ifcfg-eth1 back to dhcp
		# when boot strap it will be set to dhcp
		my @ifcfg;
		my $tmpfile = "/tmp/createifcfg$computer_node_name";
		push(@ifcfg, "DEVICE=eth1\n");
		push(@ifcfg, "BOOTPROTO=dhcp\n");
		push(@ifcfg, "STARTMODE=onboot\n");
		push(@ifcfg, "ONBOOT=yes\n");
		#write to tmpfile
		if (open(TMP, ">$tmpfile")) {
			print TMP @ifcfg;
			close(TMP);
		}
		else {
			#print "could not write $tmpfile $!\n";
			notify($ERRORS{'OK'}, 0, "could not write $tmpfile $!");
		}
		#copy to node
		if (run_scp_command($tmpfile, "$computer_node_name:/etc/sysconfig/network-scripts/ifcfg-$ETHDEVICE", $management_node_keys)) {
		}
		if (unlink($tmpfile)) {
		}
	} ## end if ($IPCONFIGURATION eq "static")

	#shutdown node
	notify($ERRORS{'OK'}, 0, "shutting down node for Linux imaging sequence");
	run_ssh_command($computer_node_name, $management_node_keys, "/sbin/shutdown -h now", "root");
	notify($ERRORS{'OK'}, 0, "sleeping for 60 seconds while machine shuts down");
	sleep 60;

	notify($ERRORS{'OK'}, 0, "returning 1");
	return 1;
} ## end sub capture_prepare

#/////////////////////////////////////////////////////////////////////////////

=head2 post_load

 Parameters  :
 Returns     :
 Description :

=cut

sub post_load {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	my $management_node_keys = $self->data->get_management_node_keys();
	my $image_name           = $self->data->get_image_name();
	my $computer_short_name  = $self->data->get_computer_short_name();
	my $computer_node_name   = $self->data->get_computer_node_name();

	notify($ERRORS{'OK'}, 0, "initiating Linux post_load: $image_name on $computer_short_name");

	# Change password
	if ($self->changepasswd($computer_node_name, "root")) {
		notify($ERRORS{'OK'}, 0, "successfully changed root password on $computer_node_name");
		#insertloadlog($reservation_id, $computer_id, "info", "SUCCESS randomized roots password");
	}
	else {
		notify($ERRORS{'OK'}, 0, "failed to edit root password on $computer_node_name");
	}
	#disable ext_sshd
	my @stopsshd = run_ssh_command($computer_short_name, $management_node_keys, "/etc/init.d/ext_sshd stop", "root");
	foreach my $l (@{$stopsshd[1]}) {
		if ($l =~ /Stopping ext_sshd/) {
			notify($ERRORS{'OK'}, 0, "ext sshd stopped on $computer_node_name");
			last;
		}
	}

	#Clear user from external_sshd_config
	my $clear_extsshd = "sed -ie \"/^AllowUsers .*/d\" /etc/ssh/external_sshd_config";
	if (run_ssh_command($computer_node_name, $management_node_keys, $clear_extsshd, "root")) {
		notify($ERRORS{'DEBUG'}, 0, "cleared AllowUsers directive from external_sshd_config");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "failed to clear AllowUsers from external_sshd_config");
	}
	
	notify($ERRORS{'DEBUG'}, 0, "calling clear_private_keys");
	#Clear ssh idenity keys from /root/.ssh 
	if ($self->clear_private_keys()) {
		notify($ERRORS{'OK'}, 0, "cleared known identity keys");
	}

	#Update Hostname to match Public assigned name
   if($self->update_public_hostname()){
      notify($ERRORS{'OK'}, 0, "Updated hostname");
   }
	
	# Run the vcl_post_load script if it exists in the image
	my $script_path = '/etc/init.d/vcl_post_load';
	my $result = $self->run_script($script_path);
	if (!defined($result)) {
		notify($ERRORS{'WARNING'}, 0, "error occurred running $script_path");
	}
	elsif ($result == 0) {
		notify($ERRORS{'DEBUG'}, 0, "$script_path does not exist in image: $image_name");
	}
	else {
		notify($ERRORS{'DEBUG'}, 0, "ran $script_path");
	}

	return 1;

} ## end sub post_load

#/////////////////////////////////////////////////////////////////////////////

=head2 post_reserve

 Parameters  :
 Returns     :
 Description :

=cut

sub post_reserve {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}
	
	my $image_name           = $self->data->get_image_name();
	my $computer_short_name  = $self->data->get_computer_short_name();
	
	notify($ERRORS{'OK'}, 0, "initiating Linux post_reserve: $image_name on $computer_short_name");
	
	# Run the vcl_post_reserve script if it exists in the image
	my $script_path = '/etc/init.d/vcl_post_reserve';
	my $result = $self->run_script($script_path);
	if (!defined($result)) {
		notify($ERRORS{'WARNING'}, 0, "error occurred running $script_path");
	}
	elsif ($result == 0) {
		notify($ERRORS{'DEBUG'}, 0, "$script_path does not exist in image: $image_name");
	}
	else {
		notify($ERRORS{'DEBUG'}, 0, "ran $script_path");
	}
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 update_public_hostname

 Parameters  :
 Returns     : 1,0 success or failure
 Description : To be used for nodes that have both private and public addresses. 
                                        Set hostname to that of the public address.

=cut

sub update_public_hostname {
     my $self = shift;
     unless (ref($self) && $self->isa('VCL::Module')) {
        notify($ERRORS{'CRITICAL'}, 0, "subroutine can only be called as a VCL::Module module object method");
        return; 
     }
         
     my $management_node_keys = $self->data->get_management_node_keys();
     my $computer_node_name   = $self->data->get_computer_node_name();
     my $image_os_type        = $self->data->get_image_os_type();
     my $image_os_name        = $self->data->get_image_os_name();
     my $computer_short_name             = $self->data->get_computer_short_name();
     my $public_hostname;

        #Get the IP address of the public adapter

 my $public_IP_address = getdynamicaddress($computer_short_name, $image_os_name, $image_os_type);
        if (!($public_IP_address)) {
                notify($ERRORS{'WARNING'}, 0, "Unable to get public IP address");
                return 0;
        }

        #Get the hostname for the public IP address
        my $get_public_hostname = "/bin/ipcalc --hostname $public_IP_address";
        my ($ipcalc_status, $ipcalc_output) = run_ssh_command($computer_short_name, $management_node_keys,$get_public_hostname);
        if (!defined($ipcalc_status)) {
                notify($ERRORS{'WARNING'}, 0, "unable to run ssh cmd $get_public_hostname on $computer_short_name");
                return 0;
        }
        elsif ("@$ipcalc_output" =~ /HOSTNAME=(.*)/i) {
                $public_hostname = $1;
                notify($ERRORS{'DEBUG'}, 0, "collected public hostname= $public_hostname");
        }

        #Set the node's hostname to public hostname
        my ($set_hostname_status, $set_hostname_output) = run_ssh_command($computer_short_name, $management_node_keys,"hostname -v $public_hostname"); 
        unless (defined($set_hostname_status) && $set_hostname_status == 0) {
			notify($ERRORS{'OK'}, 0, "failed to set public_hostname on $computer_short_name output: @${set_hostname_output}");
        }

        notify($ERRORS{'OK'}, 0, "successfully set public_hostname on $computer_short_name output: @${set_hostname_output}");
        return 1;

}
#/////////////////////////////////////////////////////////////////////////////

=head2 clear_private_keys

 Parameters  :
 Returns     :
 Description :

=cut

sub clear_private_keys {
	my $self = shift;
		unless (ref($self) && $self->isa('VCL::Module')) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine can only be called as a VCL::Module module object method");
		return;	
	}

	notify($ERRORS{'DEBUG'}, 0, "perparing to clear known identity keys");
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_short_name  = $self->data->get_computer_short_name();
	my $computer_node_name   = $self->data->get_computer_node_name();

	#Clear ssh idenity keys from /root/.ssh 
	my $clear_private_keys = "/bin/rm -f /root/.ssh/id_rsa /root/.ssh/id_rsa.pub";
	if (run_ssh_command($computer_node_name, $management_node_keys, $clear_private_keys, "root")) {
		notify($ERRORS{'DEBUG'}, 0, "cleared any id_rsa keys from /root/.ssh");
		return 1;
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "failed to clear any id_rsa keys from /root/.ssh");
		return 0;
	}

}

#/////////////////////////////////////////////////////////////////////////////

=head2 set_static_public_address

 Parameters  :
 Returns     :
 Description :

=cut

sub set_static_public_address {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}
	# Make sure public IP configuration is static
	my $ip_configuration = $self->data->get_management_node_public_ip_configuration() || 'undefined';
	unless ($ip_configuration =~ /static/i) {
		notify($ERRORS{'WARNING'}, 0, "static public address can only be set if IP configuration is static, current value: $ip_configuration");
		return;
	}

	# Get the IP configuration
	my $public_interface_name = $self->get_public_interface_name()     || 'undefined';
	my $public_ip_address     = $self->data->get_computer_ip_address() || 'undefined';

	my $subnet_mask     = $self->data->get_management_node_public_subnet_mask() || 'undefined';
	my $default_gateway = $self->get_public_default_gateway()                   || 'undefined';
	my $dns_server      = $self->data->get_management_node_public_dns_server()  || 'undefined';

	# Make sure required info was retrieved
	if ("$public_interface_name $subnet_mask $default_gateway $dns_server" =~ /undefined/) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve required network configuration:\ninterface: $public_interface_name\npublic IP address: $public_ip_address\nsubnet mask=$subnet_mask\ndefault gateway=$default_gateway\ndns server=$dns_server");
		return;
	}

	my $management_node_keys = $self->data->get_management_node_keys();
	my $image_name           = $self->data->get_image_name();
	my $computer_short_name  = $self->data->get_computer_short_name();
	my $computer_node_name   = $self->data->get_computer_node_name();

	notify($ERRORS{'OK'}, 0, "initiating Linux set_static_public_address on $computer_short_name");
	my @eth1file;
	my $tmpfile = "/tmp/ifcfg-eth_device-$computer_short_name";
	push(@eth1file, "DEVICE=eth1\n");
	push(@eth1file, "BOOTPROTO=static\n");
	push(@eth1file, "IPADDR=$public_ip_address\n");
	push(@eth1file, "NETMASK=$subnet_mask\n");
	push(@eth1file, "STARTMODE=onboot\n");
	push(@eth1file, "ONBOOT=yes\n");

	#write to tmpfile
	if (open(TMP, ">$tmpfile")) {
		print TMP @eth1file;
		close(TMP);
	}
	else {
		#print "could not write $tmpfile $!\n";

	}
	my @sshcmd = run_ssh_command($computer_short_name, $management_node_keys, "/etc/sysconfig/network-scripts/ifdown $public_interface_name", "root");
	foreach my $l (@{$sshcmd[1]}) {
		if ($l) {
			#potential problem
			notify($ERRORS{'OK'}, 0, "sshcmd output ifdown $computer_short_name $l");
		}
	}
	#copy new ifcfg-Device
	if (run_scp_command($tmpfile, "$computer_short_name:/etc/sysconfig/network-scripts/ifcfg-$public_interface_name", $management_node_keys)) {

		#confirm it got there
		undef @sshcmd;
		@sshcmd = run_ssh_command($computer_short_name, $management_node_keys, "cat /etc/sysconfig/network-scripts/ifcfg-$ETHDEVICE", "root");
		my $success = 0;
		foreach my $i (@{$sshcmd[1]}) {
			if ($i =~ /$public_ip_address/) {
				notify($ERRORS{'OK'}, 0, "SUCCESS - copied ifcfg_$public_interface_name\n");
				$success = 1;
			}
		}
		if (unlink($tmpfile)) {
			notify($ERRORS{'OK'}, 0, "unlinking $tmpfile");
		}

		if (!$success) {
			notify($ERRORS{'WARNING'}, 0, "unable to copy $tmpfile to $computer_short_name file ifcfg-$public_interface_name did get updated with $public_ip_address ");
			return 0;
		}
	} ## end if (run_scp_command($tmpfile, "$computer_short_name:/etc/sysconfig/network-scripts/ifcfg-$public_interface_name"...

	#bring device up
	@sshcmd = run_ssh_command($computer_short_name, $management_node_keys, "/etc/sysconfig/network-scripts/ifup $public_interface_name", "root");
	#should be empty
	foreach my $l (@{$sshcmd[1]}) {
		if ($l) {
			#potential problem
			notify($ERRORS{'OK'}, 0, "possible problem with ifup $public_interface_name $l");
		}
	}
	#correct route table - delete old default and add new in same line
	undef @sshcmd;
	@sshcmd = run_ssh_command($computer_short_name, $management_node_keys, "/sbin/route del default", "root");
	#should be empty
	foreach my $l (@{$sshcmd[1]}) {
		if ($l =~ /Usage:/) {
			#potential problem
			notify($ERRORS{'OK'}, 0, "possible problem with route del default $l");
		}
		if ($l =~ /No such process/) {
			notify($ERRORS{'OK'}, 0, "$l - ok  just no default route since we downed eth device");
		}
	}

	notify($ERRORS{'OK'}, 0, "Setting default route");
	undef @sshcmd;
	@sshcmd = run_ssh_command($computer_short_name, $management_node_keys, "/sbin/route add default gw $default_gateway metric 0 $public_interface_name", "root");
	#should be empty
	foreach my $l (@{$sshcmd[1]}) {
		if ($l =~ /Usage:/) {
			#potential problem
			notify($ERRORS{'OK'}, 0, "possible problem with route add default gw $default_gateway metric 0 $public_interface_name");
		}
		if ($l =~ /No such process/) {
			notify($ERRORS{'CRITICAL'}, 0, "problem with $computer_short_name $l add default gw $default_gateway metric 0 $public_interface_name");
			return 0;
		}
	} ## end foreach my $l (@{$sshcmd[1]})

	#correct external sshd file

	if (run_ssh_command($computer_short_name, $management_node_keys, "sed -ie \"/ListenAddress .*/d \" /etc/ssh/external_sshd_config", "root")) {
		notify($ERRORS{'OK'}, 0, "Cleared ListenAddress from external_sshd_config");
	}

	# Add correct ListenAddress
	if (run_ssh_command($computer_short_name, $management_node_keys, "echo \"ListenAddress $public_ip_address\" >> /etc/ssh/external_sshd_config", "root")) {
		notify($ERRORS{'OK'}, 0, "appended ListenAddress $public_ip_address to external_sshd_config");
	}

	#modify /etc/resolve.conf
	my $search;
	undef @sshcmd;
	@sshcmd = run_ssh_command($computer_short_name, $management_node_keys, "cat /etc/resolv.conf", "root");
	foreach my $l (@{$sshcmd[1]}) {
		chomp($l);
		if ($l =~ /search/) {
			$search = $l;
		}
	}

	if (defined($search)) {
		my @resolvconf;
		push(@resolvconf, "$search\n");
		my ($s1, $s2, $s3);
		if ($dns_server =~ /,/) {
			($s1, $s2, $s3) = split(/,/, $dns_server);
		}
		else {
			$s1 = $dns_server;
		}
		push(@resolvconf, "nameserver $s1\n");
		push(@resolvconf, "nameserver $s2\n") if (defined($s2));
		push(@resolvconf, "nameserver $s3\n") if (defined($s3));
		my $rtmpfile = "/tmp/resolvconf$computer_short_name";
		if (open(RES, ">$rtmpfile")) {
			print RES @resolvconf;
			close(RES);
		}
		else {
			notify($ERRORS{'OK'}, 0, "could not write to $rtmpfile $!");
		}
		#put resolve.conf  file back on node
		notify($ERRORS{'OK'}, 0, "copying in new resolv.conf");
		if (run_scp_command($rtmpfile, "$computer_short_name:/etc/resolv.conf", $management_node_keys)) {
			notify($ERRORS{'OK'}, 0, "SUCCESS copied new resolv.conf to $computer_short_name");
		}
		else {
			notify($ERRORS{'OK'}, 0, "FALIED to copied new resolv.conf to $computer_short_name");
			return 0;
		}

		if (unlink($rtmpfile)) {
			notify($ERRORS{'OK'}, 0, "unlinking $rtmpfile");
		}
	} ## end if (defined($search))
	else {
		notify($ERRORS{'WARNING'}, 0, "pulling resolve.conf from $computer_short_name failed output= @{ $sshcmd[1] }");
	}


	return 1;
} ## end sub set_static_public_address

#/////////////////////////////////////////////////////////////////////////////

=head2 get_public_interface_name

 Parameters  :
 Returns     :
 Description :

=cut

sub get_public_interface_name {

	#global varible pulled from vcld.conf
	return $ETHDEVICE;

}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_public_default_gateway

 Parameters  :
 Returns     :
 Description :

=cut

sub get_public_default_gateway {

	#global varible pulled from vcld.conf
	return $GATEWAY;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 logoff_user

 Parameters  :
 Returns     :
 Description :

=cut

sub logoff_user {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	# Make sure the user login ID was passed
	my $user_login_id = shift;
	$user_login_id = $self->data->get_user_login_id() if (!$user_login_id);
	if (!$user_login_id) {
		notify($ERRORS{'WARNING'}, 0, "user could not be determined");
		return 0;
	}

	# Make sure the user login ID was passed
	my $computer_node_name = shift;
	$computer_node_name = $self->data->get_computer_node_name() if (!$computer_node_name);
	if (!$computer_node_name) {
		notify($ERRORS{'WARNING'}, 0, "computer node name could not be determined");
		return 0;
	}

	#Make sure the identity key was passed
	my $image_identity = shift;
	$image_identity = $self->data->get_image_identity() if (!$image_identity);
	if (!$image_identity) {
		notify($ERRORS{'WARNING'}, 0, "image identity keys could not be determined");
		return 0;
	}

	my $logoff_cmd = "pkill -KILL -u $user_login_id";
	if (run_ssh_command($computer_node_name, $image_identity, $logoff_cmd, "root")) {
			notify($ERRORS{'DEBUG'}, 0, "logged off $user_login_id from $computer_node_name");
	}
	else {
		notify($ERRORS{'DEBUG'}, 0, "failed to log off $user_login_id from $computer_node_name");
	}

	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 delete_user

 Parameters  :
 Returns     :
 Description :

=cut

sub delete_user {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	# Make sure the user login ID was passed
	my $user_login_id = shift;
	$user_login_id = $self->data->get_user_login_id() if (!$user_login_id);
	if (!$user_login_id) {
		notify($ERRORS{'WARNING'}, 0, "user could not be determined");
		return 0;
	}

	# Make sure the user login ID was passed
	my $computer_node_name = shift;
	$computer_node_name = $self->data->get_computer_node_name() if (!$computer_node_name);
	if (!$computer_node_name) {
		notify($ERRORS{'WARNING'}, 0, "computer node name could not be determined");
		return 0;
	}

	#Make sure the identity key was passed
	my $image_identity = shift;
	$image_identity = $self->data->get_image_identity() if (!$image_identity);
	if (!$image_identity) {
		notify($ERRORS{'WARNING'}, 0, "image identity keys could not be determined");
		return 0;
	}
	# Use userdel to delete the user
	# Do not use userdel -r, it will affect HPC user storage for HPC installs
	my $user_delete_command = "/usr/sbin/userdel $user_login_id";
	my @user_delete_results = run_ssh_command($computer_node_name, $image_identity, $user_delete_command, "root");
	foreach my $user_delete_line (@{$user_delete_results[1]}) {
		if ($user_delete_line =~ /currently logged in/) {
			notify($ERRORS{'WARNING'}, 0, "user not deleted, $user_login_id currently logged in");
			return 0;
		}
	}

	# Delete the group
	my $user_group_cmd = "/usr/sbin/groupdel $user_login_id";
	if(run_ssh_command($computer_node_name, $image_identity, $user_delete_command, "root")){
		notify($ERRORS{'DEBUG'}, 0, "attempted to delete usergroup for $user_login_id");
	}

	my $imagemeta_rootaccess = $self->data->get_imagemeta_rootaccess();

	#Clear user from external_sshd_config
	#my $clear_extsshd = "perl -pi -e \'s/^AllowUsers .*//\' /etc/ssh/external_sshd_config";
	my $clear_extsshd = "sed -ie \"/^AllowUsers .*/d\" /etc/ssh/external_sshd_config";
	if (run_ssh_command($computer_node_name, $image_identity, $clear_extsshd, "root")) {
		notify($ERRORS{'DEBUG'}, 0, "cleared AllowUsers directive from external_sshd_config");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "failed to add AllowUsers $user_login_id to external_sshd_config");
	}

	#Clear user from sudoers

	if ($imagemeta_rootaccess) {
		#clear user from sudoers file
		my $clear_cmd = "sed -ie \"/^$user_login_id .*/d\" /etc/sudoers";
		if (run_ssh_command($computer_node_name, $image_identity, $clear_cmd, "root")) {
			notify($ERRORS{'DEBUG'}, 0, "cleared $user_login_id from /etc/sudoers");
		}
		else {
			notify($ERRORS{'CRITICAL'}, 0, "failed to clear $user_login_id from /etc/sudoers");
		}
	} ## end if ($imagemeta_rootaccess)

	return 1;

} ## end sub delete_user

#/////////////////////////////////////////////////////////////////////////////

=head2 reserve

 Parameters  : called as an object
 Returns     : 1 - success , 0 - failure
 Description : adds user 

=cut

sub reserve {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	notify($ERRORS{'DEBUG'}, 0, "Enterered reserve() in the Linux OS module");

	my $user_name            = $self->data->get_user_login_id();
	my $computer_node_name   = $self->data->get_computer_node_name();
	my $image_identity       = $self->data->get_image_identity;
	my $imagemeta_rootaccess = $self->data->get_imagemeta_rootaccess();
	my $user_standalone      = $self->data->get_user_standalone();
	my $user_uid				 = $self->data->get_user_uid();

	if($self->add_vcl_usergroup()){

	}

	my $useradd_string; 
	if(defined($user_uid) && $user_uid != 0){
		$useradd_string = "/usr/sbin/useradd -u $user_uid -d /home/$user_name -m $user_name -g vcl";
	}
	else{
		$useradd_string = "/usr/sbin/useradd -d /home/$user_name -m $user_name -g vcl";
	}


	my @sshcmd = run_ssh_command($computer_node_name, $image_identity, $useradd_string, "root");
	foreach my $l (@{$sshcmd[1]}) {
		if ($l =~ /$user_name exists/) {
			notify($ERRORS{'OK'}, 0, "detected user already has account");
			if ($self->delete_user()) {
				notify($ERRORS{'OK'}, 0, "user has been deleted from $computer_node_name");
				@sshcmd = run_ssh_command($computer_node_name, $image_identity, $useradd_string, "root");
			}
		}
	}


	if ($user_standalone) {
		notify($ERRORS{'DEBUG'}, 0, "Standalone user setting single-use password");
		my $reservation_password = $self->data->get_reservation_password();

		#Set password
		if ($self->changepasswd($computer_node_name, $user_name, $reservation_password)) {
			notify($ERRORS{'OK'}, 0, "Successfully set password on useracct: $user_name on $computer_node_name");
		}
		else {
			notify($ERRORS{'CRITICAL'}, 0, "Failed to set password on useracct: $user_name on $computer_node_name");
			return 0;
		}
	} ## end if ($user_standalone)


	#Check image profile for allowed root access
	if ($imagemeta_rootaccess) {
		# Add to sudoers file
		#clear user from sudoers file to prevent dups
		my $clear_cmd = "sed -ie \"/^$user_name .*/d\" /etc/sudoers";
		if (run_ssh_command($computer_node_name, $image_identity, $clear_cmd, "root")) {
			notify($ERRORS{'DEBUG'}, 0, "cleared $user_name from /etc/sudoers");
		}
		else {
			notify($ERRORS{'CRITICAL'}, 0, "failed to clear $user_name from /etc/sudoers");
		}
		my $sudoers_cmd = "echo \"$user_name ALL= NOPASSWD: ALL\" >> /etc/sudoers";
		if (run_ssh_command($computer_node_name, $image_identity, $sudoers_cmd, "root")) {
			notify($ERRORS{'DEBUG'}, 0, "added $user_name to /etc/sudoers");
		}
		else {
			notify($ERRORS{'CRITICAL'}, 0, "failed to add $user_name to /etc/sudoers");
		}
	} ## end if ($imagemeta_rootaccess)


	return 1;
} ## end sub reserve

#/////////////////////////////////////////////////////////////////////////////

=head2 grant_access

 Parameters  : called as an object
 Returns     : 1 - success , 0 - failure
 Description :  adds username to external_sshd_config and and starts sshd with custom config

=cut

sub grant_access {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	my $user               = $self->data->get_user_login_id();
	my $computer_node_name = $self->data->get_computer_node_name();
	my $identity           = $self->data->get_image_identity;

	notify($ERRORS{'OK'}, 0, "In grant_access routine $user,$computer_node_name");
	my @sshcmd;
	my $clear_extsshd = "sed -ie \"/^AllowUsers .*/d\" /etc/ssh/external_sshd_config";
	if (run_ssh_command($computer_node_name, $identity, $clear_extsshd, "root")) {
		notify($ERRORS{'DEBUG'}, 0, "cleared AllowUsers directive from external_sshd_config");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "failed to add AllowUsers $user to external_sshd_config");
	}

	my $cmd = "echo \"AllowUsers $user\" >> /etc/ssh/external_sshd_config";
	if (run_ssh_command($computer_node_name, $identity, $cmd, "root")) {
		notify($ERRORS{'DEBUG'}, 0, "added AllowUsers $user to external_sshd_config");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "failed to add AllowUsers $user to external_sshd_config");
		return 0;
	}

	undef @sshcmd;
	@sshcmd = run_ssh_command($computer_node_name, $identity, "/etc/init.d/ext_sshd restart", "root");

	foreach my $l (@{$sshcmd[1]}) {
		if ($l =~ /Stopping ext_sshd:/i) {
			#notify($ERRORS{'OK'},0,"stopping sshd on $computer_node_name ");
		}
		if ($l =~ /Starting ext_sshd:[  OK  ]/i) {
			notify($ERRORS{'OK'}, 0, "ext_sshd on $computer_node_name started");
		}
	}    #foreach
	notify($ERRORS{'OK'}, 0, "started ext_sshd on $computer_node_name");
	return 1;
} ## end sub grant_access

#/////////////////////////////////////////////////////////////////////////////

=head2 changepasswd

 Parameters  : called as an object
 Returns     : 1 - success , 0 - failure
 Description : changes or sets password for given account

=cut

sub changepasswd {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	my $management_node_keys = $self->data->get_management_node_keys();

	# change the privileged account passwords on the blade images
	my $node = shift; 
	my $account = shift;  
	my $passwd = shift; 

	notify($ERRORS{'WARNING'}, 0, "node is not defined")    if (!(defined($node)));
	notify($ERRORS{'WARNING'}, 0, "account is not defined") if (!(defined($account)));

	my @ssh;
	my $l;
	if ($account eq "root") {

		#if not a predefined password, get one!
		$passwd = getpw(15) if (!(defined($passwd)));
		notify($ERRORS{'OK'}, 0, "password for $node is $passwd");

		if (open(OPENSSL, "openssl passwd -1 $passwd 2>&1 |")) {
			$passwd = <OPENSSL>;
			chomp $passwd;
			close(OPENSSL);
			if ($passwd =~ /command not found/) {
				notify($ERRORS{'CRITICAL'}, 0, "failed $passwd ");
				return 0;
			}
			my $tmpfile = "/tmp/shadow.$node";
			if (open(TMP, ">$tmpfile")) {
				print TMP "$account:$passwd:13061:0:99999:7:::\n";
				close(TMP);
				if (run_ssh_command($node, $management_node_keys, "cat /etc/shadow \|grep -v $account >> $tmpfile", "root")) {
					notify($ERRORS{'DEBUG'}, 0, "collected /etc/shadow file from $node");
					if (run_scp_command($tmpfile, "$node:/etc/shadow", $management_node_keys)) {
						notify($ERRORS{'DEBUG'}, 0, "copied updated /etc/shadow file to $node");
						if (run_ssh_command($node, $management_node_keys, "chmod 600 /etc/shadow", "root")) {
							notify($ERRORS{'DEBUG'}, 0, "updated permissions to 600 on /etc/shadow file on $node");
							unlink $tmpfile;
							return 1;
						}
						else {
							notify($ERRORS{'WARNING'}, 0, "failed to change file permissions on $node /etc/shadow");
							unlink $tmpfile;
							return 0;
						}
					} ## end if (run_scp_command($tmpfile, "$node:/etc/shadow"...
					else {
						notify($ERRORS{'WARNING'}, 0, "failed to copy contents of shadow file on $node ");
					}
				} ## end if (run_ssh_command($node, $identity_key, ...
				else {
					notify($ERRORS{'WARNING'}, 0, "failed to copy contents of shadow file on $node ");
					unlink $tmpfile;
					return 0;
				}
			} ## end if (open(TMP, ">$tmpfile"))
			else {
				notify($ERRORS{'OK'}, 0, "failed could open $tmpfile $!");
			}
		} ## end if (open(OPENSSL, "openssl passwd -1 $passwd 2>&1 |"...
		return 0;
	} ## end if ($account eq "root")
	else {
		#actual user
		#push it through passwd cmd stdin
		# not all distros' passwd command support stdin
		my @sshcmd = run_ssh_command($node, $management_node_keys, "echo $passwd \| /usr/bin/passwd -f $account --stdin", "root");
		foreach my $l (@{$sshcmd[1]}) {
			if ($l =~ /authentication tokens updated successfully/) {
				notify($ERRORS{'OK'}, 0, "successfully changed local password account $account");
				return 1;
			}
		}

	} ## end else [ if ($account eq "root")

} ## end sub changepasswd

#/////////////////////////////////////////////////////////////////////////////

=head2 sanitize

 Parameters  :
 Returns     :
 Description :

=cut

sub sanitize {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $computer_node_name = $self->data->get_computer_node_name();

	# Make sure user is not connected
	if ($self->is_connected()) {
		notify($ERRORS{'WARNING'}, 0, "user is connected to $computer_node_name, computer will be reloaded");
		#return false - reclaim will reload
		return 0;
	}

	# Revoke access
	if (!$self->revoke_access()) {
		notify($ERRORS{'WARNING'}, 0, "failed to revoke access to $computer_node_name");
		#relcaim will reload
		return 0;
	}

	# Delete all user associated with the reservation
	if ($self->delete_user()) {
		notify($ERRORS{'OK'}, 0, "users have been deleted from $computer_node_name");
		return 1;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to delete users from $computer_node_name");
		return 0;
	}

	notify($ERRORS{'OK'}, 0, "$computer_node_name has been sanitized");
	return 1;
} ## end sub sanitize

#/////////////////////////////////////////////////////////////////////////////

=head2 revoke_access

 Parameters  :
 Returns     :
 Description :

=cut

sub revoke_access {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();

	if ($self->stop_external_sshd()) {
		notify($ERRORS{'OK'}, 0, "stopped external sshd");
	}

	notify($ERRORS{'OK'}, 0, "access has been revoked to $computer_node_name");
	return 1;
} ## end sub revoke_access

#/////////////////////////////////////////////////////////////////////////////

=head2 stop_external_sshd

 Parameters  :
 Returns     :
 Description :

=cut

sub stop_external_sshd {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	my $identity             = $self->data->get_image_identity;

	my @sshcmd = run_ssh_command($computer_node_name, $identity, "pkill -fx \"/usr/sbin/sshd -f /etc/ssh/external_sshd_config\"", "root");

	foreach my $l (@{$sshcmd[1]}) {
		if ($l) {
			notify($ERRORS{'DEBUG'}, 0, "output detected: $l");
		}
	}

	notify($ERRORS{'DEBUG'}, 0, "ext_sshd on $computer_node_name stopped");
	return 1;

} ## end sub stop_external_sshd
#/////////////////////////////////////////////////////////////////////////////

=head2 add_vcl_usergroup

 Parameters  : 
 Returns     : 1
 Description : step to add a user group to avoid group errors from useradd cmd 

=cut

sub add_vcl_usergroup {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	my $identity             = $self->data->get_image_identity;

	if(run_ssh_command($computer_node_name, $identity, "groupadd vcl", "root")){
		notify($ERRORS{'DEBUG'}, 0, "successfully added the vcl user group");
	}

	return 1;

}

#/////////////////////////////////////////////////////////////////////////////

=head2 is_connected

 Parameters  :
 Returns     :
 Description :

=cut

sub is_connected {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $computer_node_name = $self->data->get_computer_node_name();
	my $identity           = $self->data->get_image_identity;
	my $remote_ip          = $self->data->get_reservation_remote_ip();
	my $computer_ipaddress = $self->data->get_computer_ip_address();

	my @SSHCMD = run_ssh_command($computer_node_name, $identity, "netstat -an", "root", 22, 1);
	foreach my $line (@{$SSHCMD[1]}) {
		chomp($line);
		next if ($line =~ /Warning/);

		if ($line =~ /Connection refused/) {
			notify($ERRORS{'WARNING'}, 0, "$line");
			return 1;
		}
		if ($line =~ /tcp\s+([0-9]*)\s+([0-9]*)\s($computer_ipaddress:22)\s+([.0-9]*):([0-9]*)(.*)(ESTABLISHED)/) {
			return 1;
		}
	} ## end foreach my $line (@{$SSHCMD[1]})

	return 0;

} ## end sub is_connected

#/////////////////////////////////////////////////////////////////////////////

=head2 call_post_load_custom

 Parameters  : none
 Returns     : If successfully ran post_load_custom script: 1
               If post_load_custom script does not exist: 1
               If error occurred: false
 Description : Checks if /etc/init.d/post_load_custom script exists on the
               Linux node and attempts to run it. This script can be created by
					the image creator and will run when the image is loaded.

=cut

sub call_post_load_custom {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Check if post_load_custom exists
	my $post_load_custom_path = '/etc/init.d/post_load_custom';
	if ($self->filesystem_entry_exists($post_load_custom_path)) {
		notify($ERRORS{'DEBUG'}, 0, "post_load_custom script exists: $post_load_custom_path");
	}
	else {
		notify($ERRORS{'OK'}, 0, "post_load_custom script does NOT exist: $post_load_custom_path");
		return 1;
	}
	
	# Get the node configuration directory, make sure it exists, create if necessary
	my $node_log_directory = $self->get_node_configuration_directory() . '/Logs';
	if (!$self->create_directory($node_log_directory)) {
		notify($ERRORS{'WARNING'}, 0, "failed to create node log file directory: $node_log_directory");
		return;
	}
	
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	
	# Assemble the log file path
	my $post_load_custom_log_path = $node_log_directory . "/post_load_custom.log";
	
	# Assemble the command
	my $post_load_custom_command;
	# Make sure the script is readable and executable
	$post_load_custom_command .= "chmod +rx \"$post_load_custom_path\"";
	# Redirect the script output to the log file path
	$post_load_custom_command .= " && \"$post_load_custom_path\" >> \"$post_load_custom_log_path\" 2>&1";
	
	# Execute the command
	my ($post_load_custom_exit_status, $post_load_custom_output) = run_ssh_command($computer_node_name, $management_node_keys, $post_load_custom_command, '', '', 1);
	if (defined($post_load_custom_exit_status) && $post_load_custom_exit_status == 0) {
		notify($ERRORS{'OK'}, 0, "executed $post_load_custom_path, exit status: $post_load_custom_exit_status");
	}
	elsif (defined($post_load_custom_exit_status)) {
		notify($ERRORS{'WARNING'}, 0, "$post_load_custom_path returned a non-zero exit status: $post_load_custom_exit_status, output:\n@{$post_load_custom_output}");
		return 0;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to execute $post_load_custom_path");
		return;
	}

	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 run_script

 Parameters  : script path
 Returns     : If successfully ran  script: 1
               If  script does not exist: 0
               If error occurred: undefined
 Description : Checks if script exists on the Linux node and attempts to run it.

=cut

sub run_script {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the script path argument
	my $script_path = shift;
	if (!$script_path) {
		notify($ERRORS{'WARNING'}, 0, "script path argument was not specified");
		return;
	}
	
	# Check if script exists
	if ($self->filesystem_entry_exists($script_path)) {
		notify($ERRORS{'DEBUG'}, 0, "script exists: $script_path");
	}
	else {
		notify($ERRORS{'OK'}, 0, "script does NOT exist: $script_path");
		return 0;
	}
	
	# Determine the script name
	my ($script_name) = $script_path =~ /\/([^\/]+)$/;
	notify($ERRORS{'DEBUG'}, 0, "script name: $script_name");
	
	# Get the node configuration directory, make sure it exists, create if necessary
	my $node_log_directory = $self->get_node_configuration_directory() . '/Logs';
	if (!$self->create_directory($node_log_directory)) {
		notify($ERRORS{'WARNING'}, 0, "failed to create node log file directory: $node_log_directory");
		return;
	}
	
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	
	# Assemble the log file path
	my $log_file_path = $node_log_directory . "/$script_name.log";
	notify($ERRORS{'DEBUG'}, 0, "script log file path: $log_file_path");
	
	# Assemble the command
	my $command = "chmod +rx \"$script_path\" && \"$script_path\" >> \"$log_file_path\" 2>&1";
	
	# Execute the command
	my ($exit_status, $output) = run_ssh_command($computer_node_name, $management_node_keys, $command, '', '', 1);
	if (defined($exit_status) && $exit_status == 0) {
		notify($ERRORS{'OK'}, 0, "executed $script_path, exit status: $exit_status");
	}
	elsif (defined($exit_status)) {
		notify($ERRORS{'WARNING'}, 0, "$script_path returned a non-zero exit status: $exit_status");
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to execute $script_path");
		return;
	}

	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 create_directory

 Parameters  : directory path
 Returns     : If successful: true
               If failed: false
 Description : Creates a directory on the Linux node. If a multi-level
               directory path is specified, parent directories are also created
					if they do not exist.

=cut

sub create_directory {
	my $self = shift;
	if (ref($self) !~ /module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Make sure path argument was specified
	my $path = shift;
	if (!$path) {
		notify($ERRORS{'WARNING'}, 0, "directory path argument was not specified");
		return;
	}
	
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();

	# Assemble the mkdir command and execute it
	my $mkdir_command = "mkdir -p \"$path\" && ls -d \"$path\"";
	my ($mkdir_exit_status, $mkdir_output) = run_ssh_command($computer_node_name, $management_node_keys, $mkdir_command, '', '', 1);
	if (defined($mkdir_output) && grep(/ls: /, @$mkdir_output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to create directory on $computer_node_name: $path, exit status: $mkdir_exit_status, output:\n@{$mkdir_output}");
		return;
	}
	elsif (defined($mkdir_exit_status)) {
		notify($ERRORS{'OK'}, 0, "directory created on $computer_node_name: $path, output:\n@{$mkdir_output}");
		return 1;
	}
	elsif (defined($mkdir_exit_status)) {
		notify($ERRORS{'WARNING'}, 0, "failed to create directory on $computer_node_name: $path, exit status: $mkdir_exit_status, output:\n@{$mkdir_output}");
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to delete file on $computer_node_name: $path");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 filesystem_entry_exists

 Parameters  : filesystem path
 Returns     : If entry exists: 1
               If entry does not exist: 0
					If error occurred: undefined
 Description : Checks if a filesystem entry (file or directory) exists on the
					Linux node.

=cut

sub filesystem_entry_exists {
	my $self = shift;
	if (ref($self) !~ /module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the path from the subroutine arguments and make sure it was passed
	my $path = shift;
	if (!$path) {
		notify($ERRORS{'WARNING'}, 0, "unable to detmine if file exists, path was not specified as an argument");
		return;
	}
	
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	
	# Assemble the dir command and execute it
	my $ls_command = "ls -l \"$path\"";
	my ($ls_exit_status, $ls_output) = run_ssh_command($computer_node_name, $management_node_keys, $ls_command, '', '', 1);
	if (defined($ls_output) && grep(/no such file/i, @$ls_output)) {
		notify($ERRORS{'DEBUG'}, 0, "filesystem entry does NOT exist on $computer_node_name: $path");
		return 0;
	}
	elsif ((defined($ls_exit_status) && $ls_exit_status == 0) || (defined($ls_output) && grep(/$path/i, @$ls_output))) {
		notify($ERRORS{'DEBUG'}, 0, "filesystem entry exists on $computer_node_name: $path, dir output:\n" . join("\n", @$ls_output));
		return 1;
	}
	elsif ($ls_exit_status) {
		notify($ERRORS{'WARNING'}, 0, "failed to determine if filesystem entry exists on $computer_node_name: $path, exit status: $ls_exit_status, output:\n@{$ls_output}");
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to determine if filesystem entry exists on $computer_node_name: $path");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

1;
__END__

=head1 SEE ALSO

L<http://cwiki.apache.org/VCL/>

=cut
