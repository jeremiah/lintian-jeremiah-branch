# -*- perl -*-
# Lintian::Tag::Info -- interface to tag metadata

# Copyright (C) 1998 Christian Schwarz and Richard Braakman
# Copyright (C) 2009 Russ Allbery
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

package Lintian::Tag::Info;

use strict;
use warnings;

use Carp qw(croak);

use Lintian::Output qw(debug_msg);
use Text_utils qw(dtml_to_html dtml_to_text split_paragraphs wrap_paragraphs);
use Util qw(fail read_dpkg_control);

# The URL to a web man page service.  NAME is replaced by the man page
# name and SECTION with the section to form a valid URL.  This is used
# when formatting references to manual pages into HTML to provide a link
# to the manual page.
our $MANURL
    = 'http://manpages.debian.net/cgi-bin/man.cgi?query=NAME&sektion=SECTION';

# Stores the parsed tag information for all known tags.  Loaded the first
# time new() is called.
our %INFO;

# Stores the parsed manual reference data.  Loaded the first time info()
# is called.
our %MANUALS;

=head1 NAME

Lintian::Tag::Info - Lintian interface to tag metadata

=head1 SYNOPSIS

    my $tag = Lintian::Tag::Info->new('some-tag');
    print "Tag info is:\n";
    print $tag_info->description('text', '   ');
    print "\nTag info in HTML is:\n";
    print $tag_info->description('html', '   ');

=head1 DESCRIPTION

This module provides an interface to tag metadata as gleaned from the
*.desc files describing the checks.  Currently, it is only used to format
and return the tag description, but it provides a framework that can be
used to retrieve other metadata about tags.

=head1 CLASS METHODS

=over 4

=item new(TAG)

Creates a new Lintian::Tag::Info object for the given TAG.  Returns undef
if the tag is unknown and throws an exception if there is a parse error
reading the check description files or if TAG is not specified.

The first time this method is called, all tag metadata will be loaded into
a memory cache.  This information will be used to satisfy all subsequent
Lintian::Tag::Info object creation, avoiding multiple file reads.  This
however means that a running Lintian process will not notice changes to
tag metadata on disk.

=cut

# Load all tag data into the %INFO hash.  Called by new() if %INFO is
# empty and hence called the first time new() is called.
sub _load_tag_data {
    my $root = $ENV{LINTIAN_ROOT} || '/usr/share/lintian';
    for my $desc (<$root/checks/*.desc>) {
        debug_msg(2, "Reading checker description file $desc ...");
        my ($header, @tags) = read_dpkg_control($desc);
        unless ($header->{'check-script'}) {
            fail("missing Check-Script field in $desc");
        }
        for my $tag (@tags) {
            unless ($tag->{tag}) {
                fail("missing Tag field in $desc");
            }
            $tag->{info} = '' unless exists($tag->{info});
            $INFO{$tag->{tag}} = $tag;
        }
    }
}

# Create a new object for the given tag.  We just use the hash created by
# read_dpkg_control as the object, which means we slowly bless the objects
# in %INFO as we return them.
sub new {
    my ($class, $tag) = @_;
    croak('no tag specified') unless $tag;
    _load_tag_data() unless %INFO;
    if ($INFO{$tag}) {
        my $self = $INFO{$tag};
        bless($self, $class) unless ref($self) eq $class;
        return $self;
    } else {
        return;
    }
}

=back

=head1 INSTANCE METHODS

=over 4

=item description([FORMAT [, INDENT]])

Returns the formatted description (the Info field) for a tag.  FORMAT must
be either C<text> or C<html> and defaults to C<text> if no format is
specified.  If C<text>, returns wrapped paragraphs formatted in plain text
with a right margin matching the Text::Wrap default, preserving as
verbatim paragraphs that begin with whitespace.  If C<html>, return
paragraphs formatted in HTML.

If INDENT is specified, the string INDENT is prepended to each line of the
formatted output.

=cut

# Load manual reference data into %MANUALS.  This information doesn't have
# a single unique key and has multiple data values per key, so we don't
# try to use the Lintian::Data interface.  Instead, we read a file
# delimited by double colons.  We do use a path similar to Lintian::Data
# to keep such files in the same general location.
sub _load_manual_data {
    my $root = $ENV{LINTIAN_ROOT} || '/usr/share/lintian';
    open(REFS, '<', "$root/data/output/manual-references")
        or fail("can't open $root/data/output/manual-references: $!");
    local $_;
    while (<REFS>) {
        chomp;
        next if /^\#/;
        next if /^\s*$/;
        next unless /^(.+?)::(.*?)::(.+?)::(.*?)$/;
        my ($manual, $section, $title, $url) = split('::');
        $MANUALS{$manual}{$section}{title} = $title;
        $MANUALS{$manual}{$section}{url} = $url;
    }
    close REFS;
}

# Format a reference to a manual in the HTML that Lintian uses internally
# for tag descriptions and return the result.  Takes the name of the
# manual and the name of the section.  Returns an empty string if the
# argument isn't a known manual.
sub _manual_reference {
    my ($manual, $section) = @_;
    _load_manual_data unless %MANUALS;
    return '' unless exists $MANUALS{$manual}{''};

    # Start with the reference to the overall manual.
    my $title = $MANUALS{$manual}{''}{title};
    my $url   = $MANUALS{$manual}{''}{url};
    my $text  = $url ? qq(<a href="$url">$title</a>) : $title;

    # Add the section information, if present, and a direct link to that
    # section of the manual where possible.
    if ($section and $section =~ /^[A-Z]+$/) {
        $text .= " appendix $section";
    } elsif ($section and $section =~ /^\d+$/) {
        $text .= " chapter $section";
    } elsif ($section and $section =~ /^[A-Z\d.]+$/) {
        $text .= " section $section";
    }
    if ($section and exists $MANUALS{$manual}{$section}) {
        my $title = $MANUALS{$manual}{$section}{title};
        my $url   = $MANUALS{$manual}{$section}{url};
        $text .= qq[ (<a href="$url">$title</a>)];
    }

    return $text;
}

# Format the contents of the Ref attribute of a tag.  Handles manual
# references in the form <keyword> <section>, manpage references in the
# form <manpage>(<section>), and URLs.
sub _format_reference {
    my ($field) = @_;
    my @refs;
    for my $ref (split(/,\s*/, $field)) {
        my $text;
        if ($ref =~ /^([\w-]+)\s+(.+)$/) {
            $text = _manual_reference($1, $2);
        } elsif ($ref =~ /^([\w_-]+)\((\d\w*)\)$/) {
            my ($name, $section) = ($1, $2);
            my $url = $MANURL;
            $url =~ s/NAME/$name/g;
            $url =~ s/SECTION/$section/g;
            $text = qq(the <a href="$url">$ref</a> manual page);
        } elsif ($ref =~ m,^(ftp|https?)://,) {
            $text = qq(<a href="$ref">$ref</a>);
        }
        push (@refs, $text) if $text;
    }

    # Now build an English list of the results with appropriate commas and
    # conjunctions.
    my $text = '';
    if ($#refs >= 2) {
        $text = join(', ', splice(@refs, 0, $#refs));
        $text = "Refer to $text, and @refs for details.";
    } elsif ($#refs >= 0) {
        $text = 'Refer to ' . join(' and ', @refs) . ' for details.';
    }
    return $text;
}

# Returns the formatted tag description.
sub description {
    my ($self, $format, $indent) = @_;
    $indent = '' unless defined($indent);
    $format = 'text' unless defined($format);
    if ($format ne 'text' and $format ne 'html') {
        croak("unknown output format $format");
    }

    # Build the tag description.
    my $info = $self->{info};
    $info =~ s/\n[ \t]/\n/g;
    my @text = split_paragraphs($info);
    if ($self->{ref}) {
        push(@text, '', _format_reference($self->{ref}));
    }
    if ($self->{severity} and $self->{certainty}) {
        my $severity = $self->{severity};
        my $certainty = $self->{certainty};
        push(@text, '', "Severity: $severity, Certainty: $certainty");
    }
    if ($self->{experimental}) {
        push(@text, '',
             'This tag is marked experimental, which means that the code that'
             . ' generates it is not as well-tested as the rest of Lintian'
             . ' and might still give surprising results.  Feel free to'
             . ' ignore experimental tags that do not seem to make sense,'
             . ' though of course bug reports are always welcomed.');
    }

    # Format and return the output.
    if ($format eq 'text') {
        return wrap_paragraphs($indent, dtml_to_text(@text));
    } elsif ($format eq 'html') {
        return wrap_paragraphs('HTML', $indent, dtml_to_html(@text));
    }
}

=back

=head1 DIAGNOSTICS

The following exceptions may be thrown:

=over 4

=item no tag specified

The Lintian::Tag::Info::new constructor was called without passing a tag
as an argument.

=item unknown output format %s

An unknown output format was passed as the FORMAT argument of
description().  FORMAT must be either C<text> or C<html>.

=back

The following fatal internal errors may be reported:

=over 4

=item can't open %s: %s

The specified file, which should be part of the standard Lintian data
files, could not be opened.  The file may be missing or have the wrong
permissions.

=item missing Check-Script field in %s

The specified check description file has no Check-Script field in its
header section.  This probably indicates the file doesn't exist or has
some significant formatting error.

=item missing Tag field in %s

The specified check description file has a tag section that has no Tag
field.

=back

=head1 FILES

=over 4

=item LINTIAN_ROOT/checks/*.desc

The tag description files, from which tag metadata is read.  All files
matching this shell glob expression will be read looking for tag data.

=item LINTIAN_ROOT/data/output/manual-references

Information about manual references.  Each non-comment, non-empty line of
this file contains four fields separated by C<::>.  The first field is the
name of the manual, the second field is the section or empty for data
about the whole manual, the third field is the title, and the fourth field
is the URL.  The URL is optional.

=back

=head1 ENVIRONMENT

=over 4

=item LINTIAN_ROOT

This variable specifies Lintian's root directory.  It defaults to
F</usr/share/lintian> if not set.  The B<lintian> program normally takes
care of setting it.

=back

=head1 AUTHOR

Originally written by Russ Allbery <rra@debian.org> for Lintian.

=head1 SEE ALSO

lintian(1)

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 ts=4 et shiftround
