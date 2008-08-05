package Spread::Client;

use 5.006;
use strict;
use warnings;

use bytes;
use Spread::Client::Constant ':all';
use Spread::Client::Frame;
use List::Util qw(reduce);
use Socket;

our $VERSION = '0.03_02';

sub connect {
    my %args = @_;

    my ($port, $host) = split /@/, $args{spread_name};
    
    die "Bad/missing SPREAD NAME.\n"
        unless defined $port;

    my $connect_class = $args{connect_class} ? "Spread::Client::Connection::$args{connect_class}"
                                             : "Spread::Client::Connection::Sync";

    eval "require $connect_class";

    die $@
        if $@;

    my $conn = $connect_class->new( @_ )
                or die "Could not connect to spread daemon: $!\n";

    my $sock = $conn->sock;

    # In case connection class sets socket to non-blocking
    # we will set this to non-blocking again below
    unless( defined $sock->blocking( 1 ) ) {
         die "could not set blocking on handle: $!\n";
    }

    # CONNECT ROUTINE
    unless( $conn->is_unix ) {

        my $addr = sockaddr_in($port, inet_aton( $host ));
        connect( $sock, $addr)
            or die "Could not connect to host: $host\n";
    }

    # TODO revisit this at a later date
    my $connect_message = build_connect_message( private_name => $args{private_name} || 0);
    
    # Send connect message
    $conn->write( \$connect_message );
    
    # read buffer
    my $buffer;

    # Get auth methods length, to find what auth methods we have available
    $buffer = $conn->read( 1 );
    my $authlen = ord( $$buffer );
    
    die "Bad authentication length: $authlen\n"
        if $authlen == -1 or $authlen >= 128;
    
    # Get auth methods
    my $auth_method = $conn->read( $authlen );
    
    # Send auth message
    my $auth_method_message = build_auth_message( auth_method => $$auth_method );
    $conn->write( \$auth_method_message );
    
    # Pull down accept and versions and grouplen
    $buffer = $conn->read( 5 );
    
    my (@versions, $accept, $full_version);

    # Get accept
    $accept = unpack('c', $$buffer);

    die "Did not get accept: $accept\n"
        unless $accept == 1;
    #

    $versions[0] = substr( $$buffer, 1, 1); # Major
    $versions[1] = substr( $$buffer, 2, 1); # Minor
    $versions[2] = substr( $$buffer, 3, 1); # Patch

    {
        no warnings 'once';
        $full_version = unpack('c', reduce { $a | $b } (@versions));
    }

    die "Full version is a problem: $full_version\n"
        if $full_version == -1;

    # Get private group info
    # Get group length
    my $grouplen = unpack('c', substr($$buffer, 4, 1));
    
    die "We had an issue with the group length\n"
        if $grouplen == -1;

    # Get actual name private group name
    $buffer = $conn->read( $grouplen );
    my $private_group = unpack("a*", $$buffer);
    $conn->private_group( $private_group );

    if( $conn->is_async ) {
        $sock->blocking( 0 );
        $conn->listen_for_messages;
        $conn->session_connected( 1 );
    }

    return $conn;
}

sub receive {
    my %args = @_;

    if( $args{conn}->is_async ) {

        $args{conn}->receive;

        unless( $args{conn}->message_callback ) {
            return $args{conn}->get_queued_messages;
        }
    }
    else {
        my $buffer;
    
        # pull down message header
        $buffer = $args{conn}->read( 48 );
        
        # define variables we need
        my ($mess_type, $endian);
    
        # unpack header data
        my ($service_type, $sender, $num_members, $hint, $data_len) = parse_message_header( $buffer );
    
        # Get group data
        my $pull_bytes = $num_members * 32;
        $buffer = $args{conn}->read( $pull_bytes );

        my $groups = parse_message_groups( $buffer, $num_members); 
    
        # pull down message body
        $buffer = $args{conn}->read( $data_len );
    
        my $message = parse_message_body( $buffer, $service_type);
    
        return ($service_type, $sender, $groups, $mess_type, $endian, $message);
    }
}

sub multicast {
    my %args = @_;

    my $private_group = $args{conn}->private_group;

    my $multi_message = build_standard_message( type       => $args{type} || DEFAULT_SEND_MESS,
                                                from_group => $private_group,
                                                to_groups  => $args{groups},
                                                data       => $args{message},
                                             );

    my $ret = $args{conn}->write( \$multi_message );

    return $ret;
}

sub join {
    my %args = @_;

    my $private_group = $args{conn}->private_group;

    my $join_message = build_standard_message( type       => JOIN_MESS,
                                               from_group => $private_group,
                                               to_groups  => $args{groups},
                                            );

    my $ret = $args{conn}->write( \$join_message );

    return $ret;
}

sub leave {
    my %args = @_;

    my $private_group = $args{conn}->private_group;

    my $leave_message = build_standard_message( type       => LEAVE_MESS,
                                                from_group => $private_group,
                                                to_groups  => $args{groups},
                                             );

    my $ret = $args{conn}->write( \$leave_message );

    return $ret;
}

sub disconnect {
    my %args = @_;

    my $private_group = $args{conn}->private_group;

    my $disconnect_message = build_standard_message( type       => KILL_MESS,
                                                     from_group => $private_group,
                                                     to_groups  => [ $private_group ],
                                                  );
    # write close message to daemon
    $args{conn}->write( \$disconnect_message );

    # close socket
    $args{conn}->close();
}

1;
__END__

=head1 NAME

Spread::Client - Spread client that allows synchronous OR asynchronous multicast/receive/join/leave/disconnect to spread daemons

=head1 SYNOPSIS

  # ASYNCHRONOUS AnyEvent BEHAVIOR(with POE)
  use strict;
  use warnings;
  use POE;
  use Spread::Client;
  use Spread::Client::Constant ':all'; 
  use Danga::Socket;
  use Data::Dumper;
  
  my $spread_name = '4803@localhost';
  my $private_name = 'mrperla';
  
  
  # set message count before exit
  my $message_max = 10;
  my $message_count = 0;
  
  # Connect using Danga socket connection class for 
  # running with Danga::Socket Event loop
  my $conn = Spread::Client::connect(
        spread_name   => $spread_name,
        private_name  => $private_name,
        connect_class => 'Async::AnyEvent',
     );
  
  # set callback to handle message receipts
  $conn->message_callback( \&handle_message );
  
  Spread::Client::join( conn   => $conn,
                        groups => ['channel-100'],
                      );
  
  # If you decide not to give this message a 'type'
  # then it will default to sending a RELIABLE MESSAGE
  Spread::Client::multicast( conn    => $conn,
                             groups  => ['channel-100'],
                             message => 'this is a message',
                           );

  sub handle_message {
      my ($conn, @message) = @_;
  
      print Dumper( \@message );
  
      $message_count++;
  
      if( $message_count >= $message_max ) {
  
          Spread::Client::leave( conn   => $conn,
                                 groups => ['channel-100'],
                              );
  
          Spread::Client::disconnect( conn => $conn );
          POE::Kernel->stop();
      }
  }

  # Don't forget to start your event loop  
  POE::Kernel->run();

  # ASYNCHRONOUS DANGA BEHAVIOR
  use strict;
  use warnings;
  use Spread::Client;
  use Spread::Client::Constant ':all';
  use Danga::Socket;
  use Data::Dumper;
  
  my $spread_name = '4803@localhost';
  my $private_name = 'mrperla';
  
  
  # set message count before exit
  my $message_max = 10;
  my $message_count = 0;
  
  # Connect using Danga socket connection class for 
  # running with Danga::Socket Event loop
  my $conn = Spread::Client::connect(
        spread_name   => $spread_name,
        private_name  => $private_name,
        connect_class => 'Async::Danga',
     );
  
  # set callback to handle message receipts
  $conn->message_callback( \&handle_message );
  
  Spread::Client::join( conn   => $conn,
                        groups => ['channel-100'],
                      );
  
  # If you decide not to give this message a 'type'
  # then it will default to sending a RELIABLE MESSAGE
  Spread::Client::multicast( conn    => $conn,
                             groups  => ['channel-100'],
                             message => 'this is a message',
                           );

  sub handle_message {
      my ($conn, @message) = @_;
  
      print Dumper( \@message );
  
      $message_count++;
  
      if( $message_count >= $message_max ) {
  
          Spread::Client::leave( conn   => $conn,
                                 groups => ['channel-100'],
                              );
  
          Spread::Client::disconnect( conn => $conn );
          Danga::Socket->SetPostLoopCallback( sub { 0 } );
      }
  }
  # Don't forget to start your event loop  
  Danga::Socket->EventLoop();

  # SYNCHRONOUS BEHAVIOR
  use strict;
  use warnings;
  use Spread::Client;
  use Spread::Client::Constant ':all';
  use Data::Dumper;
  
  my $spread_name = '4803@localhost';
  my $private_name = 'mrperls';
  
  # Connect using Sync class
  # if connect_class is left out, defaults to 'Sync'
  my $conn = Spread::Client::connect(
        spread_name   => $spread_name,
        private_name  => $private_name,
        connect_class => 'Sync',
     );
  
  # If we need the private group
  my $private_group = $conn->private_group;
  
  Spread::Client::join( conn   => $conn,
                        groups => ['channel-100'],
                      );
  
  Spread::Client::multicast( conn    => $conn,
                             type => SAFE_MESS,
                             groups  => ['channel-100'],
                             message => 'this is a message',
                           );
  
  for (1..2) {
  
      my ($service_type, $sender, $groups, $mess_type, $endian, $message) =
      Spread::Client::receive( conn  => $conn );

      # Should Dump a join message, and our multi-cast since SELF_DISCARD isn't on
      warn Dumper( $service_type, $sender, $groups, $mess_type, $endian, $message);
  }
  
  # leave group
  Spread::Client::leave( conn   => $conn,
                         groups => ['channel-100'],
                       );

  # disconnect
  Spread::Client::disconnect( conn => $conn );

=head1 DESCRIPTION

A Spread Toolkit client implemented in perl, that allows both synchronous and asynchronous functionality.
Reading the Spread User's Guide is strongly recommended before using the Spread Toolkit in general.

=head1 CAVEATS

Right now connect is always synchronous, this may change later but unless someone really wants it
i don't see it occuring anytime soon.  Asynchronous is supported for Danga::Socket and AnyEvent which should
cover a large number of the event loops out there, include POE.  If you would like to use AnyEvent or Danga, please have them installed, it's not a prerequisite of the module as connection classes are loaded at runtime and the synchronous connection client does not depend on either Danga::Socket or AnyEvent.

=head1 EXPORT

None by default.


=head1 SEE ALSO

Constants module L<Spread::Client::Constant>.

Without these helpful sources, this module would not have been possible:

Rough spread API, documented by a nice developer. L<http://www.roughtrade.net/spread/spread-client-proto.txt>

Pure Python Spread Client L<http://code.google.com/p/py-spread/>

Spread source including their C and JAVA client L<http://www.spread.org/>

=head1 AUTHOR

Marlon Bailey, E<lt>mbailey@span.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Marlon Bailey

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
