#
# DB_File::Lock
#
# by David Harris <dharris@drh.net>
#
# Copyright (c) 1999-2000 David R. Harris. All rights reserved. 
# This program is free software; you can redistribute it and/or modify it 
# under the same terms as Perl itself. 
#

# We rename the package so that we don't have to package it separately.
# package DB_File::Lock;
package Devscripts::DB_File_Lock;

require 5.004;

use strict;
use vars qw($VERSION @ISA $locks);

@ISA = qw(DB_File);
$VERSION = '0.05';

use DB_File ();
use Fcntl qw(:flock O_RDWR O_RDONLY O_WRONLY O_CREAT);
use Carp qw(croak carp);
use Symbol ();

# import function can't be inherited, so this magic required
sub import
{
	my $ourname = shift;
	my @imports = @_; # dynamic scoped var, still in scope after package call in eval
	my $module = caller;
	my $calling = $ISA[0];
	eval " package $module; import $calling, \@imports; ";
}

sub _lock_and_tie
{
	my $package = shift;

	## Grab the type of tie

	my $tie_type = pop @_;

	## There are two ways of passing data defined by DB_File

	my $lock_data;
	my @dbfile_data;

	if ( @_ == 5 ) {
		$lock_data = pop @_;
		@dbfile_data = @_;
	} elsif ( @_ == 2 ) {
		$lock_data = pop @_;
		@dbfile_data = @{$_[0]};
	} else {
		croak "invalid number of arguments";
	}

	## Decipher the lock_data

	my $mode;
	my $nonblocking   = 0;
	my $lockfile_name = $dbfile_data[0] . ".lock";
	my $lockfile_mode;

	if ( lc($lock_data) eq "read" ) {
		$mode = "read";
	} elsif ( lc($lock_data) eq "write" ) {
		$mode = "write";
	} elsif ( ref($lock_data) eq "HASH" ) {
		$mode = lc $lock_data->{mode};
		croak "invalid mode ($mode)" if ( $mode ne "read" and $mode ne "write" );
		$nonblocking = $lock_data->{nonblocking};
		$lockfile_name = $lock_data->{lockfile_name} if ( defined $lock_data->{lockfile_name} );
		$lockfile_mode = $lock_data->{lockfile_mode};
	} else {
		croak "invalid lock_data ($lock_data)";
	}

	## Warn about opening a lockfile for writing when only locking for reading

	# NOTE: This warning disabled for RECNO because RECNO seems to require O_RDWR
	# even when opening only for reading.

	carp "opening with write access when locking only for reading (use O_RDONLY to fix)"
		if (
			( $dbfile_data[1] && O_RDWR or $dbfile_data[1] && O_WRONLY ) # any kind of write access
			and $mode eq "read"                                          # and opening for reading
			and $tie_type ne "TIEARRAY"                                  # and not RECNO
		);

	## Determine the mode of the lockfile, if not given

	# THEORY: if someone can read or write the database file, we must allow 
	# them to read and write the lockfile.

	if ( not defined $lockfile_mode ) {
		$lockfile_mode = 0600; # we must be allowed to read/write lockfile
		$lockfile_mode |= 0060 if ( $dbfile_data[2] & 0060 );
		$lockfile_mode |= 0006 if ( $dbfile_data[2] & 0006 );
	 }

	## Open the lockfile, lock it, and open the database

	my $lockfile_fh = Symbol::gensym();
	my $saved_umask = umask(0000) if ( umask() & $lockfile_mode );
	my $open_ok = sysopen($lockfile_fh, $lockfile_name, O_RDWR|O_CREAT,
            $lockfile_mode);
	umask($saved_umask) if ( defined $saved_umask );
	$open_ok or croak "could not open lockfile ($lockfile_name)";

	my $flock_flags = ($mode eq "write" ? LOCK_EX : LOCK_SH) | ($nonblocking ? LOCK_NB : 0);
	if ( not flock $lockfile_fh, $flock_flags ) {
		close $lockfile_fh;
		return undef if ( $nonblocking );
		croak "could not flock lockfile";
	}

	my $self = $tie_type eq "TIEHASH"
		? $package->SUPER::TIEHASH(@_)
		: $package->SUPER::TIEARRAY(@_);
	if ( not $self ) {
		close $lockfile_fh;
		return $self;
	}

	## Store the info for the DESTROY function

	my $id = "" . $self;
	$id =~ s/^[^=]+=//; # remove the package name in case re-blessing occurs
	$locks->{$id} = $lockfile_fh;

	## Return the object

	return $self;
}

sub TIEHASH
{
	return _lock_and_tie(@_, 'TIEHASH');
}

sub TIEARRAY
{
	return _lock_and_tie(@_, 'TIEARRAY');
}

sub DESTROY
{
	my $self = shift;

	my $id = "" . $self;
	$id =~ s/^[^=]+=//;
	my $lockfile_fh = $locks->{$id};
	delete $locks->{$id};

	$self->SUPER::DESTROY(@_);

	# un-flock not needed, as we close here
	close $lockfile_fh;
}





1;
__END__

=head1 NAME

DB_File::Lock - Locking with flock wrapper for DB_File

=head1 SYNOPSIS

 use DB_File::Lock;
 use Fcntl qw(:flock O_RDWR O_CREAT);

 $locking = "read";
 $locking = "write";
 $locking = {
     mode            => "read",
     nonblocking     => 0,
     lockfile_name   => "/path/to/shared.lock",
     lockfile_mode   => 0600,
 };

 [$X =] tie %hash,  'DB_File::Lock', $filename, $flags, $mode, $DB_HASH, $locking;
 [$X =] tie %hash,  'DB_File::Lock', $filename, $flags, $mode, $DB_BTREE, $locking;
 [$X =] tie @array, 'DB_File::Lock', $filename, $flags, $mode, $DB_RECNO, $locking;

 # or place the DB_File arguments inside a list reference:
 [$X =] tie %hash,  'DB_File::Lock', [$filename, $flags, $mode, $DB_HASH], $locking;

 ...use the same way as DB_File for the rest of the interface...

=head1 DESCRIPTION

This module provides a wrapper for the DB_File module, adding locking.

When you need locking, simply use this module in place of DB_File and
add an extra argument onto the tie command specifying if the file should
be locked for reading or writing.

The alternative is to write code like:

  open(LOCK, "<$db_filename.lock") or die;
  flock(LOCK, LOCK_SH) or die;
  tie(%db_hash, 'DB_File', $db_filename,  O_RDONLY, 0600, $DB_HASH) or die;
  ... then read the database ...
  untie(%db_hash);
  close(LOCK);

This module lets you write

  tie(%db_hash, 'DB_File::Lock', $db_filename,  O_RDONLY, 0600, $DB_HASH, 'read') or die;
  ... then read the database ...
  untie(%db_hash);

This is better for two reasons:

(1) Less cumbersome to write.

(2) A fatal exception in the code working on the database which does
not lead to process termination will probably not close the lockfile
and therefore cause a dropped lock.

=head1 USAGE DETAILS

Tie to the database file by adding an additional locking argument
to the list of arguments to be passed through to DB_File, such as:

  tie(%db_hash, 'DB_File::Lock', $db_filename,  O_RDONLY, 0600, $DB_HASH, 'read');

or enclose the arguments for DB_File in a list reference:

  tie(%db_hash, 'DB_File::Lock', [$db_filename,  O_RDONLY, 0600, $DB_HASH], 'read');

The filename used for the lockfile defaults to "$filename.lock"
(the filename of the DB_File with ".lock" appended). Using a lockfile
separate from the database file is recommended because it prevents weird
interactions with the underlying database file library

The additional locking argument added to the tie call can be:

(1) "read" -- acquires a shared lock for reading

(2) "write" -- acquires an exclusive lock for writing

(3) A hash with the following keys (all optional except for the "mode"):

=over 4

=item mode 

the locking mode, "read" or "write".

=item lockfile_name 

specifies the name of the lockfile to use. Default
is "$filename.lock".  This is useful for locking multiple resources with
the same lockfiles.

=item nonblocking 

determines if the flock call on the lockfile should
block waiting for a lock, or if it should return failure if a lock can
not be immediately attained. If "nonblocking" is set and a lock can not
be attained, the tie command will fail.  Currently, I'm not sure how to
differentiate this between a failure form the DB_File layer.

=item lockfile_mode 

determines the mode for the sysopen call in opening
the lockfile. The default mode will be formulated to allow anyone that
can read or write the DB_File permission to read and write the lockfile.
(This is because some systems may require that one have write access to
a file to lock it for reading, I understand.) The umask will be prevented
from applying to this mode.

=back

Note: One may import the same values from DB_File::Lock as one may import
from DB_File.

=head1 GOOD LOCKING ETIQUETTE

To avoid locking problems, realize that it is B<critical> that you release
the lock as soon as possible. See the lock as a "hot potato", something
that you must work with and get rid of as quickly as possible. See the
sections of code where you have a lock as "critical" sections. Make sure
that you call "untie" as soon as possible.

It is often better to write:

  # open database file with lock
  # work with database
  # lots of processing not related to database
  # work with database
  # close database and release lock

as:

  # open database file with lock
  # work with database
  # close database and release lock
  
  # lots of processing not related to database
  
  # open database file with lock
  # work with database
  # close database and release lock

Also realize that when acquiring two locks at the same time, a deadlock
situation can be caused.

You can enter a deadlock situation if two processes simultaneously try to
acquire locks on two separate databases. Each has locked only one of
the databases, and cannot continue without locking the second. Yet this
will never be freed because it is locked by the other process. If your
processes all ask for their DB files in the same order, this situation
cannot occur.

=head1 OTHER LOCKING MODULES

There are three locking wrappers for DB_File in CPAN right now. Each one
implements locking differently and has different goals in mind. It is
therefore worth knowing the difference, so that you can pick the right
one for your application.

Here are the three locking wrappers:

Tie::DB_Lock -- DB_File wrapper which creates copies of the database file
for read access, so that you have kind of a multiversioning concurrent
read system. However, updates are still serial. Use for databases where
reads may be lengthy and consistency problems may occur.

Tie::DB_LockFile -- DB_File wrapper that has the ability to lock and
unlock the database while it is being used. Avoids the tie-before-flock
problem by simply re-tie-ing the database when you get or drop a
lock. Because of the flexibility in dropping and re-acquiring the lock
in the middle of a session, this can be massaged into a system that will
work with long updates and/or reads if the application follows the hints
in the POD documentation.

DB_File::Lock (this module) -- extremely lightweight DB_File wrapper
that simply flocks a lockfile before tie-ing the database and drops the
lock after the untie.  Allows one to use the same lockfile for multiple
databases to avoid deadlock problems, if desired. Use for databases where
updates are reads are quick and simple flock locking semantics are enough.

(This text duplicated in the POD documentation, by the way.)

=head1 AUTHOR

David Harris <dharris@drh.net>

Helpful insight from Stas Bekman <stas@stason.org>

=head1 SEE ALSO

DB_File(3).

=cut
