=head1 NAME

Class::DBI::utf8 - A Class:::DBI subclass that knows about UTF-8

=head1 SYNOPSIS

This module is a Class::DBI plugin:

  package Foo;
  use base qw( Class::DBI );
  use Class::DBI::utf8;

  ...
  __PACKAGE__->columns( All => qw( id text other ) );

  # the text column contains utf8-encoded character data
  __PACKAGE__->utf8_columns(qw( text ));
  ...
  
  # create an object with a nasty character.
  my $foo = Foo->create({
    text => "a \x{2264} b for some a",
  });
  
  # search for utf8 chars.
  Foo->search( text => "a \x{2264} b for some a" );

=head1 DESCRIPTION

Rather than have to think about things like character sets, I prefer to have
my objects just Do The Right Thing. I also want utf-8 encoded byte strings in
the database whenever possible. Using this subclass of Class::DBI, I can just
put perl strings into the properties of an object, and the right thing will
always go into the database and come out again.

For example, without Class::DBI::utf8,

  MyObject->create({ id => 1, text => "\x{2264}" }); # a less-than-or-equal-to symbol

..will create a row in the database containing (probably) the utf-8 byte
encoding of the less-than-or-equal-to symbol. But when trying to retrieve the
object again..

  my $broken = MyObject->retrieve( 1 );
  my $text = $broken->text;

... $text will (probably) contain 3 characters and look nothing like a
less-than-or-equal-to symbol. Likewise, you will be unable to search properly
for strings containing non-ascii characters.

Creating objects with simpler non-ascii characters from the latin-1 range 
will lead to even stranger behaviours:

  my $e_acute = "\x{e9}"; # an e-acute
  MyObject->create({ text => $e_acute });

  utf8::upgrade($e_acute); # still the same letter, but with a different
                           # internal representation
  MyObject->create({ text => $e_acute });

This will create two rows in the database - the first containing the latin-1
encoded bytes of an e-acute character (or the database may refuse to let you
create the row, if it's been set up to require utf-8), the latter containing
the utf-8 encoded bytes of an e-acute.  In the latter case you won't get an
e-acute back out again if you retrieve the row; You'll get a string
containing two characters, one for each byte of the utf-8 encoding.

Because of this, if you're handling data from an outside source, you won't
really have any clear idea of what will be going into the database at all.

Fortunately, simply adding the lines:

  use Class::DBI::utf8;
  __PACKAGE__->utf8_columns("text");

will make all these operations work much more as expected - the database will
always contain utf-8 bytes, you will always get back the characters you put
in, and you will instantly become the most popular person at work.

This module assumes that the underlying database and driver don't know
anything about character sets, and just store bytes. Some databases, for
instance postgresql and later versions of mysql, allow you to create tables
with utf-8 character sets, but the Perl DB drivers don't respect this and
still require you to pass utf-8 bytes, and return utf-8 bytes and hence 
still need special handling with Class::DBI.

Class::DBI::utf8 will do the right thing in both cases, and I would
suggest you tell the database to use utf-8 encoding as well as using
Class::DBI::utf8 where possible.

=head1 CAVEATS

This module requires perl 5.8.0 or later - if you're still using 5.6, and you
want to use unicode, I suggest you don't. It's not nice.

Be aware that utf-8 encoded strings will commonly have a byte length greater
than their character length - this is because non-ascii characters such as
e-actute will encode to two bytes, and other characters can be encoded to
other numbers of bytes, although 2 or 3 bytes are typical. If your database
has an underlying data type of a limited length, for instance a CHAR(10), you
may not be able to store 10 characters in it.

Internally, the module is futzing with the _utf8_on and _utf8_off methods. If
you don't know I<why> doing that is probably a bad idea, you should read into
it before you start trying to do this sort of thing yourself. I'd prefer to
use encode_utf8 and decode_utf8, but I have my reasons for doing it this way
- mostly, it's so that we can allow for DBD drivers that do know about
character sets.

Finally, the database may have some internal string-handling functions, for
instance LOWER(), UPPER(), various sorting functions, etc. I<If> the database
is properly utf-8 aware, it I<may> do the right thing to the utf-8 encoded
strings in the database if you use these functions. But I've never seen a
database do the right thing. Likewise, there are all sorts of nasty
normalisation considerations when performing searches that are outside of the
scope of these docs to discuss, but which can really ruin your day.

=head1 BUGS

I've attempted to make the module keep doing the Right Thing even when the
DBD driver for the database knows what it's doing, ie, if you give it
sensible perl strings it'll store the right thing in the database and recover
the right thing from the database. However, I've been forced to assume that,
in this eventuality, the database driver will hand back strings that already
have the utf-8 bit set. If they don't, things I<will> break. On the bright
side, they'll break really fast. I also find it extremely unlikely that
anyone would bother reducing strings to latin1 internally.

Also, I've been forced to override the _do_search method to make searching
for utf8 strings work, so if you override it locally as well, bad things
will happen. Sorry.

Incredible popularity and fame gained through understanding of utf-8 may not
actually be real.

=head1 SEE ALSO

L<Class::DBI>

=head1 AUTHOR

Tom Insam <tinsam@fotango.com>

Copyright Fotango 2005.  All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut


package Class::DBI::utf8;
use warnings;
use strict;
use Encode qw( encode_utf8 decode_utf8 );
use utf8;
use base qw( Exporter Class::Data::Inheritable );
use Class::DBI;

our $VERSION = 0.2;


# export the following functions..
our @EXPORT = (qw(  utf8_all_columns utf8_columns ));

# add an accessor to store which columns are utf8-enabled
Class::DBI->mk_classdata('_utf8_columns');

sub utf8_all_columns {
  my $class = shift;
  $class->utf8_columns( $class->columns('All') );
}

sub utf8_columns {
  my $class = shift;
  # the default
  $class->_utf8_columns([]) unless $class->_utf8_columns;

  # a getter?
  return @{ $class->_utf8_columns } unless @_;

  my @columns = @_;
  push @{ $class->_utf8_columns }, @columns;

  $class->add_trigger($_ => sub { 
    my ($self) = @_;
    for (@columns) {
      next if ref($self->{$_});
      utf8::upgrade( $self->{$_} ) if defined($self->{$_});
    }

  }) for qw( before_create before_update );

  $class->add_trigger(select => sub { 
    my ($self) = @_;

    for (@columns) {
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

sub import {
  my $class = shift;
  local $Exporter::ExportLevel = 1;
  if ($_[0] && $_[0] eq "-nosearch") {
    shift; # ignore option
    return $class->SUPER::import(@_);
  }
  if (caller(0)->isa('Class::DBI')) {
    caller(0)->add_searcher(search => "Class::DBI::utf8::Search");
  }
  $class->SUPER::import(@_);
}


package Class::DBI::utf8::Search;
use base 'Class::DBI::Search::Basic';

sub bind {
  my $self = shift;

  # for fast lookup of which cols are utf8
  my %hash = map { $_ => 1 } $self->class->utf8_columns;

  # get name => values of columns to search for
  my $search_for = $self->_search_for();
  
  # make an array that says whether the value at that position should be 
  # upgraded to utf8. This relies on ->bind() sorting the keys from _search_for()
  # in the same way.
  my @utf8cols = map { $hash{$_} && defined($search_for->{$_}) } sort keys %$search_for;
  
  # take copy of array to avoid upgrading the original values; we only want to
  # upgrade the values for the search.
  my @bind = @{ $self->SUPER::bind(@_) };

  my $i = 0;
  for (@bind) {   
    if (shift @utf8cols) {
      my $copy = $_;
      utf8::upgrade($copy);
      $bind[$i] = $copy;
    }
    $i++;
  }
  \@bind;
}

1;
