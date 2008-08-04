use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Spread::Client',
    VERSION_FROM      => 'lib/Spread/Client.pm', # finds $VERSION
    PREREQ_PM         => { 'Spread::Client::Constant' => 0.02,
                           'IO::Socket::INET'         => 0,
                           'IO::Socket::UNIX'         => 0,
                           'Socket'                   => 0,
                         }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Spread/Client.pm', # retrieve abstract from module
       AUTHOR         => 'Marlon Bailey <mbailey@cpan.org>') : ()),
);
