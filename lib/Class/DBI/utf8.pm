=head1 NAME

Class::DBI::utf8 - A Class:::DBI subclass that knows about UTF8

=head1 SYNOPSIS

Exactly as Class::DBI:

  package Foo;
  use base qw( Class::DBI );
  use Class::DBI::utf8;

  ...
  __PACKAGE__->utf8_columns(qw( text ));
  ...
  
  # create an object with a nasty character.
  my $foo = Foo->create({
    text => "a \x{2264} b for some a",
  });

=head1 DESCRIPTION

Rather than have to think about things like character sets, I prefer to
have my objects just Do The Right Thing. I also want utf-8 encoded byte
strings in the database whenever possible. Using this subclass of Class::DBI,
I can just put perl strings into the properties of an object, and the
right thing will always go into the database and come out again.

This module requires perl 5.8.0 or later - if you're still using 5.6, and
you want to use unicode, I suggest you don't. It's not nice.

This module _assumes_ that the underlying DBD driver doesn't know anything
about character sets, and is just storing bytess. If you're using something
like DBD::Pg, which _does_ know about charsets, you don't need this module.
Having said, that, I've tried to write it in such a way that if the DBD
driver _does_ know about charsets, we won't break. (see L<BUGS>)

Internally, the module is futzing with the _utf8_on and _utf8_off methods.
If you don't know _why_ doing that is probably a bad idea, you should read
into it before you start trying to do this sort of thing yourself. I'd
_prefer_ to use encode_utf8 and decode_utf8, but I have my reasons for 
doing it this way - mostly, it's so that we can allow for DBD drivers that
know about charsets.

=head1 BUGS

I've attempted to make the module _keep_ doing the Right Thing even when
the DBD driver for the database _does_ know what it's doing, ie, if you
give it sensible perl strings it'll store the right thing in the database
and recover the right thing from the database. However, I've been forced
to assume that, in this eventuality, the database driver will hand back
strings that already have the utf-8 bit set. If they don't, things _will_
break. On the bright side, they'll break really fast.

=head1 AUTHOR

Tom Insam <tinsam@fotango.com>

=cut

package Class::DBI::utf8;
use warnings;
use strict;
use base qw( Exporter );
our @EXPORT = (qw( _do_search ));

our $VERSION = 0.1;

use Encode qw( encode_utf8 decode_utf8 );
use utf8;

sub import {
  # export functions as normal
  __PACKAGE__->export_to_level(1, @_);

  my $caller = caller;
  unless (UNIVERSAL::isa($caller, "Class::DBI")) {
    warn "caller $caller is not a Class::DBI subclass, using "
         .__PACKAGE__." here is probably not what you want.\n";
    return;
  }
  
  $caller->add_trigger($_ => sub { 
    my ($self) = @_;
    for ($self->columns('All')) {
      next if ref($self->{$_});
      utf8::upgrade( $self->{$_} ) if defined($self->{$_});
    }

  }) for qw( before_create before_update );

  $caller->add_trigger(select => sub { 
    my ($self) = @_;

    for ($self->columns('All')) {
      next if ref($self->{$_});

      # flip the bit..
      Encode::_utf8_on($self->{$_}) if defined($self->{$_});

      # ..sanity check
      if (defined($self->{$_}) and !utf8::valid($self->{$_})) {
        # if we're in an eval, let's at least not _completely_ stuff
        # the process. Turn the bit off again.
        Encode::_utf8_off($self->{$_});
        # ..and die
        $self->_croak("Invalid UTF8 from database in column '$_'");
      }
    }
  });

}

# ick, we have to override this so we can utf8-encode the search
# terms. Bug in Class::DBI?
sub _do_search {
  my ($proto, $search_type, @args) = @_;
  @args = %{ $args[0] } if ref $args[0] eq "HASH";

  for (my $i = 1; $i < @args; $i += 2) { # odd elements only
    utf8::upgrade($args[$i]) unless ref($args[$i]);
  }
  # SUPER is handled at compile-time. Bugger.
  $proto->Class::DBI::_do_search($search_type, @args);
}

1;
