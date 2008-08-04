package Spread::Client::Connection;
use strict;
use warnings;

use IO::Socket::INET;
use IO::Socket::UNIX;
use Socket;

sub create_new_socket {
    my $self = shift;
    my %args = @_;

    my ($port, $host) = split(/\@/, $args{spread_name} );
    my $sock;

    if( defined $port and defined $host ) { # INET socket

        $sock = IO::Socket::INET->new( Proto    => 'tcp',
                                       Type     => SOCK_STREAM,
                                    )
                    or die "Could not create IP socket '$port\@$host' because: $!";
    }
    elsif( defined $port ) { # UNIX socket

        $sock = IO::Socket::UNIX->new( Peer     => "/tmp/$port",
                                       Type     => SOCK_STREAM,
                                    )
                    or die "Could not create UNIX socket '/tmp/$port' because: $!\n";
    }
    else {
        die "Not enough information to creata a socket to the Spread daemon\n";
    }

    return $sock;
}

sub is_unix {
    my $self = shift;

    return $self->sock->isa('IO::Socket::UNIX');
}

sub session_connected {
    my $self = shift;

    if( $_[0] ) {
        $self->{session_connected} = $_[0];
    }

    $self->{session_connected};
}

1;
