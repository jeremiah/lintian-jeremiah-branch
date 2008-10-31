# Copyright © 2008 Frank Lichtenheld <frank@lichtenheld.de>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

package Lintian::Command;
use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(spawn reap);

use IPC::Run qw(run harness);

=head1 NAME

Lintian::Command - Utilities to execute other commands from lintian code

=head1 SYNOPSIS

    use Lintian::Command qw(spawn);

    # simplest possible call
    my $success = spawn({}, ['command']);

    # catch output
    my $opts = {};
    $success = spawn($opts, ['command']);
    if ($success) {
	print "STDOUT: $opts->{out}\n";
	print "STDERR: $opts->{err}\n";
    }

    # from file to file
    $opts = { in => 'infile.txt', out => 'outfile.txt' };
    $success = spawn($opts, ['command']);

    # piping
    $success = spawn({}, ['command'], "|", ['othercommand']);

=head1 DESCRIPTION

Lintian::Command is a thin wrapper around IPC::Run, that catches exception
and implements a useful default behaviour for input and output redirection.

Lintian::Command provides a function spawn() which is a wrapper
around IPC::Run::run() resp. IPC::Run::start() (depending on whether a
pipe is requested).  To wait for finished child processes, it also
provides the reap() function as a wrapper around IPC::Run::finish().

=head2 C<spawn($opts, @cmds)>

The @cmds array is given to IPC::Run::run() (or ::start()) unaltered, but
should only be used for commands and piping symbols (i.e. all of the elements
should be either an array reference, a code reference, '|', or '&').  I/O
redirection is handled via the $opts hash reference. If you need more fine
grained control than that, you should just use IPC::Run directly.

$opts is a hash reference which can be used to set options and to retrieve
the status and output of the command executed.

The following hash keys can be set to alter the behaviour of spawn():

=over 4

=item in

STDIN for the first forked child.  Defaults to C<\undef>.

=item pipe_in

Use a pipe for STDIN and start the process in the background.
You will need to close the pipe after use and call $opts->{harness}->finish
in order for the started process to end properly.

=item out

STDOUT of the last forked child.  Will be set to a newly created
scalar reference by default which can be used to retrieve the output
after the call.

=item pipe_out

Use a pipe for STDOUT and start the process in the background.
You will need to call $opts->{harness}->finish in order for the started
process to end properly.

=item err

STDERR of all forked childs.  Defaults to STDERR of the parent.

=item pipe_err

Use a pipe for STDERR and start the process in the background.
You will need to call $opts->{harness}->finish in order for the started
process to end properly.

=item fail

Configures the behaviour in case of errors. The default is 'exception',
which will cause spawn() to die in case of exceptions thrown by IPC::Run.
If set to 'error' instead, it will also die if the command exits
with a non-zero error code.  If exceptions should be handled by the caller,
setting it to 'never' will cause it to store the exception in the
C<exception> key instead.

=back

The following additional keys will be set during the execution of spawn():

=over 4

=item harness

Will contain the IPC::Run object used for the call which can be used to
query the exit values of the forked programs (E.g. with results() and
full_results()) and to wait for processes started in the background.

=item exception

If an exception is raised during the execution of the commands,
and if C<fail> is set to 'never', the exception will be caught and
stored under this key.

=item success

Will contain the return value of spawn().

=back

=cut

sub spawn {
    my ($opts, @cmds) = @_;

    if (ref($opts) ne 'HASH') {
	$opts = {};
    }
    $opts->{fail} ||= 'exception';

    my ($out, $pipe);
    my (@out, @in, @err);
    if ($opts->{pipe_in}) {
	@in = ('<pipe', $opts->{pipe_in});
	$pipe = 1;
    } else {
	$opts->{in} ||= \undef;
	@in = ('<', $opts->{in});
    }
    if ($opts->{pipe_out}) {
	@out = ('>pipe', $opts->{pipe_out});
	$pipe = 1;
    } else {
	$opts->{out} ||= \$out;
	@out = ('>', $opts->{out});
    }
    if ($opts->{pipe_err}) {
	@err = ('2>pipe', $opts->{pipe_err});
	$pipe = 1;
    } else {
	$opts->{err} ||= \*STDERR;
	@err = ('2>', $opts->{err});
    }

    use Data::Dumper;
#    print STDERR Dumper($opts, \@cmds);
    eval {
	if (@cmds == 1) {
	    $opts->{harness} = harness($cmds[0], @in, @out, @err);
	} else {
	    my $first = shift @cmds;
	    $opts->{harness} = harness($first, @in, @cmds, @out, @err);
	}

	if ($pipe) {
	    $opts->{success} = $opts->{harness}->start;
	} else {
	    $opts->{success} = $opts->{harness}->run;
	}
    };
    if ($@) {
	require Util;
	Util::fail($@) if $opts->{fail} ne 'never';
	$opts->{success} = 0;
	$opts->{exception} = $@;
    } elsif ($opts->{fail} eq 'error'
	     and !$opts->{success}) {
	require Util;
	if ($opts->{description}) {
	    Util::fail("$opts->{description} failed with error code ".
		       $opts->{harness}->result);
	} elsif (@cmds == 1) {
	    Util::fail("$cmds[0][0] failed with error code ".
		       $opts->{harness}->result);
	} else {
	    Util::fail("command failed with error code ".
		       $opts->{harness}->result);
	}
    }
#    print STDERR Dumper($opts, \@cmds);
    return $opts->{success};
}

=head 2 C<reap($opts)>

If you used one of the C<pipe_*> options to spawn(), you will need to wait
for your child processes to finish.  For this you can use the reap() function,
which you can call with the $opts hash reference you gave to spawn() and which
will do the right thing.

Note however that this function will not close any of the pipes for you, so
you probably want to do that first before calling this function.

The following keys of the $opts hash have roughly the same function as
for spawn():

=over 4

=item harness

=item fail

=item success

=item exception

=back

All other keys are probably just ignored.

=cut

sub reap {
    my ($opts) = @_;

    return unless defined($opts->{harness});

    eval {
	$opts->{success} = $opts->{harness}->finish;
    };
    if ($@) {
	require Util;
	Util::fail($@) if $opts->{fail} ne 'never';
	$opts->{success} = 0;
	$opts->{exception} = $@;
    } elsif ($opts->{fail} eq 'error'
	     and !$opts->{success}) {
	require Util;
	if ($opts->{description}) {
	    Util::fail("$opts->{description} failed with error code ".
		       $opts->{harness}->result);
	} else {
	    Util::fail("command failed with error code ".
		       $opts->{harness}->result);
	}
    }
    return $opts->{success};
}

1;
__END__

=head1 EXPORTS

Lintian::Command exports nothing by default, but you can export the
spawn() and reap() functions.

=head1 AUTHOR

Originally written by Frank Lichtenheld <djpig@debian.org> for Lintian.

=head1 SEE ALSO

lintian(1), IPC::Run

=cut