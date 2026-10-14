#!/usr/bin/perl
# Turns the JSON that `contacts-cli search --format json` prints (an array of
# contacts) into Alfred Script Filter JSON.
#
#   to_script_filter.pl <message-flag> <query> < contacts.json
#
# Each phone number becomes its own row, so the number you pick is the one that is
# copied (Enter) or messaged (⌘↩). Holding shift shows the contact's first email
# and ⇧↩ opens a mailto: link to it. A contact with no number gets one row for
# its first email, and one with neither is listed but can't be selected.
#
# Uses only Perl and JSON::PP, which macOS ships.
use strict;
use warnings;
use Encode qw(decode);
use JSON::PP ();

my ($flag, $query) = @ARGV;
$flag  = '--signal' unless defined $flag && length $flag;
$query = '' unless defined $query;
$query = decode('UTF-8', $query);

my $json = JSON::PP->new->utf8->canonical;

local $/;
my $contacts = $json->decode(scalar <STDIN>);
die "expected a JSON array of contacts\n" unless ref $contacts eq 'ARRAY';

my $true  = JSON::PP::true;
my $false = JSON::PP::false;

my @items;
for my $contact (@$contacts) {
    next unless ref $contact eq 'HASH';

    my $name   = $contact->{name} // '';
    my @phones = grep { defined && length } @{ $contact->{phones} // [] };
    my @emails = grep { defined && length } @{ $contact->{emails} // [] };
    my $email  = $emails[0];
    my $org    = $contact->{organization};
    my $suffix = defined $org && length $org ? " \x{b7} $org" : '';

    my $shift = defined $email
        ? { valid => $true, arg => $email, subtitle => $email }
        : { valid => $false, subtitle => 'No email address' };

    my @targets = @phones ? @phones : (defined $email ? ($email) : ());

    if (!@targets) {
        push @items, {
            uid          => "contact-$name",
            title        => $name,
            subtitle     => "No phone number or email$suffix",
            autocomplete => $name,
            valid        => $false,
        };
        next;
    }

    for my $target (@targets) {
        push @items, {
            uid          => "contact-$name-$target",
            title        => $name,
            subtitle     => "$target$suffix",
            arg          => $target,
            autocomplete => $name,
            valid        => $true,
            text         => { copy => $target, largetype => $target },
            mods         => {
                cmd   => { valid => $true, arg => $target, subtitle => "Message with $flag" },
                shift => $shift,
            },
        };
    }
}

if (!@items) {
    @items = ({
        title    => "No contacts matching '$query'",
        subtitle => 'Import contacts with: contacts-cli import <file.csv>',
        valid    => $false,
    });
}

print $json->encode({ items => \@items }), "\n";
