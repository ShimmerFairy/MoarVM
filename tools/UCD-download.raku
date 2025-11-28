#!/usr/bin/env raku
# Gets the latest Unicode Data files and extracts them.
use v6;
my $unicode-ftp = "ftp://ftp.unicode.org/Public";
my $UCD-zip     = "$unicode-ftp/UCD/latest/ucd/UCD.zip";
my $UCA-allkeys = "$unicode-ftp/UCA/latest/allkeys.txt";
my $UCA-test    = "$unicode-ftp/UCA/latest/CollationTest.zip";
my $MAPPINGS    = "$unicode-ftp/MAPPINGS";
my @CODETABLES  =
    'VENDORS/MICSFT/WINDOWS/CP1252.TXT',
    'VENDORS/MICSFT/WINDOWS/CP1251.TXT';
my $JIS-url     = "https://encoding.spec.whatwg.org/index-jis0208.txt";

sub MAIN {
    quit "Must run in the top level of a checked-out MoarVM git repo."
        unless '.git'.IO.d;

    my IO::Path $unidata = 'UNIDATA'.IO.absolute.IO;
    quit "$unidata directory already exists. Please delete it and run again."
        if $unidata.e;

    say "Creating new UNIDATA directory";
    mkdir $unidata;

    indir $unidata, {
        download-zip-file($UCD-zip);
        download-zip-file($UCA-test, 'UCA');
        indir 'UCA', { download-files($UCA-allkeys) };

        say "\nDownloading codetables from $MAPPINGS";
        mkdir 'CODETABLES';
        indir 'CODETABLES', {
            download-files("$MAPPINGS/$_") for @CODETABLES;
            download-files($JIS-url);
        }

        get-emoji;
    }
}

sub quit($message) {
    note $message;
    exit;
}

sub read-url($url) {
    qqx{curl --ftp-method nocwd -s "$url"}
}

sub download-files(+@urls) {
    if @urls == 1 {
        my $filename = @urls[0].subst(/^.*\//, '');
        say "\nDownloading $filename from @urls[0]";
    }
    temp %*ENV<COLUMNS> = 80;
    ?run < curl -# --ftp-method nocwd --remote-name-all >, |@urls;
}

sub download-zip-file(Str:D $url, Str:D $dir = '.') {
    unless $dir.IO.d {
        say "\nCreating the $dir subdirectory";
        mkdir $dir;
    }

    indir $dir, {
        my $filename = $url.subst(/^.*\//, '');
        download-files($url);
        run 'unzip', $filename;
    }
}

sub get-emoji {
    # Since emoji sequence names are not canonical and unchangeable, we get
    # all of them starting with the first the feature was added in
    my $first-emoji-ver = v4.0;

    say "\nGetting a listing of available Emoji versions";

    # list of pairs, version => base url. Not a hash so we can preserve the sorted order.
    my @emoji-vers = read-url("$unicode-ftp/emoji/").lines.map(*.split(/' '+/)[8]).grep(/^\d/);
    @emoji-vers.=map({Pair.new($_, "$unicode-ftp/emoji/$_")});

    # Note: since version 17.0, emoji files have been moved to
    # /Public/<version>/emoji, which means this script won't find any further
    # versions at the previous URL.
    {
        my @possible-extra-vers = read-url("$unicode-ftp/").lines.map(*.split(/' '+/)[8]).grep(/^\d/);
        @possible-extra-vers.=grep({/^(\d+)/; +~$0 >= 17}); # don't bother with versions < 17.0.0
        @possible-extra-vers.=map({Pair.new($_, "$unicode-ftp/$_/emoji")});
        @emoji-vers.append: @possible-extra-vers if +@possible-extra-vers;
    }

    my @sorted-emoji-versions = @emoji-vers.grep(/^\d/).sort(*.key.Version);

    say "Emoji versions found: ", @sorted-emoji-versions».key.join(' ');

    my @to-download = < ReadMe.txt emoji-data.txt emoji-sequences.txt
                        emoji-zwj-sequences.txt emoji-test.txt >;

    for @sorted-emoji-versions.reverse.grep($first-emoji-ver <= *.key.Version) -> $version {
        put "\nEmoji version $version.key():";
        my $emoji-data-url = $version.value;
        my $readme = read-url("$emoji-data-url/ReadMe.txt").chomp;
        if $readme.match(/draft|PRELIMINARY/, :i) {
            say "Looks like this version is a draft. ReadMe.txt text: <<$readme>>";
            next;
        }
        else {
            my @urls = @to-download.map({ "$emoji-data-url/$_" });
            say "Fetching: @to-download[]";

            my $emoji-folder = "emoji-$version.key()".IO;
            $emoji-folder.mkdir;
            note "Downloading to $emoji-folder";
            indir $emoji-folder, { download-files(@urls) };
        }
    }
}
