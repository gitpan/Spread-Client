package Spread::Client::Connection::Async::Danga;
use strict;
use warnings;
use base qw/Danga::Socket Spread::Client::Connection::Async/;

use fields keys %Spread::Client::Connection::Async::init;

sub listen_for_messages {
    my Spread::Client::Connection::Async::Danga $self = shift;
    $self->watch_read( $_[0] || 1 );
}

sub new {
    my Spread::Client::Connection::Async::Danga $class = shift;
    my %args = @_;

    my $self = fields::new( $class )
        unless ref $class;


    $self->SUPER::new( $self->create_new_socket( @_ ) );
    $self->init;

    return $self;
}

sub read {
    my $self = shift;

    my $len = $_[0];
    my $read_buffer;

    do {

        my $buffer = $self->SUPER::read( $len );
        $read_buffer .= $$buffer;
        $len = $_[0] - length $read_buffer;
    } while( $len > 0 and !$_[1]);

    return \$read_buffer;
}

sub event_read {
    my Spread::Client::Connection::Async::Danga $self = shift;
    $self->receive();
}

sub event_hup {
    my Spread::Client::Connection::Async::Danga $self = shift;

    $self->close();
}

sub event_err {
    my Spread::Client::Connection::Async::Danga $self = shift;

    $self->close();
}

1;
