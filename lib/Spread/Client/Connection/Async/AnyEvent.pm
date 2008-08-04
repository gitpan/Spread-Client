package Spread::Client::Connection::Async::AnyEvent;
use strict;
use warnings;
use base qw/Spread::Client::Connection::Async/;
use AnyEvent;
use AnyEvent::Handle;

sub new {
    my $class = shift;
    my %args = @_;

    my $socket = $class->create_new_socket( @_ );
    my $handle =
      AnyEvent::Handle->new (
         fh       => $socket,
         autocork => 0,
    );
    
    $handle->stop_read;

    my $self = { sock => $socket, handle => $handle };
    bless $self, $class;
    $self->init;

    return $self;
}

sub sock {
    my $self = shift;
    return $self->{sock};
}

sub write {
    my $self = shift;
    $self->{handle}->push_write( ${$_[0]} );
}

sub listen_for_messages {
    my $self = shift;

    $self->{handle}->start_read;
    $self->{handle}->on_read( sub { $self->receive } );
}

sub read {
    my $self = shift;

    my $read_buffer;

    if( $self->session_connected ) {
        $read_buffer = substr( $self->{handle}->{rbuf}, 0, $_[0]);
        $self->{handle}->{rbuf} = substr( $self->{handle}->{rbuf}, $_[0]);
    }
    else {
        my $len = $_[0];
        my $sock = $self->sock;

        do {
    
            my $buffer;
            my $ret = sysread( $sock, $buffer, $len);
            $read_buffer .= $buffer;
            $len = $_[0] - length $read_buffer;
        } while( $len > 0 and !$_[1]);
    }

    return \$read_buffer;
}

sub close {
    my $self = shift;
    $self->{sock}->close();
}

1;
