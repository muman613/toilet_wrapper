#!/usr/bin/perl
###############################################################################
#	MODULE		:	Toilet_Wrapper.pl
#	CODENAME	:	poo.pl
#	PROJECT		:	Front-end for toilet ASCII art program
#	PROGRAMMER	:	M. Uman
#	DATE		:	October 28, 2008
#	LAST MOD	:	November 28, 2008
###############################################################################
#	NOTE		:	Uses the 'toilet'
###############################################################################
#     ___ ____ _ _    ____ ___     _ _ _ ____ ____ ___  ___  ____ ____ 
#      |  |  | | |    |___  |      | | | |__/ |__| |__] |__] |___ |__/ 
#      |  |__| | |___ |___  |  ___ |_|_| |  \ |  | |    |    |___ |  \ 
#
###############################################################################

use strict;
#use warnings;

#use File::Spec; # portable path manipulations
#use Gtk2::SimpleList;   # easy wrapper for list views
use Gtk2 '-init'; # auto-initialize Gtk2
use Gtk2::GladeXML;
use Gnome2::GConf;
use List::Util qw(first);
use Encode qw(decode encode);
use File::Find;

my $version = "1.11a";
my $install_prefix = "/usr/share/toiletwrapper/";
my $glade = undef;
my $mainwin;
my $text_view;
my $user_text;
my $font_combo;
my $aboutDialog;
my @fonts;
my $theme_name = undef; # "theme#1";
my @themes = (
		{
			NAME => 'Blue on Yellow',
			BG => { red => 0xff00, green => 0xff00, blue => 0x8000 },
			FG => { red => 0x8000, green => 0x0000, blue => 0xf000 },
		},
		{
			NAME => 'White on Orange',
			BG => { red => 0xffff, green => 0x8c00, blue => 0x0000 },
			FG => { red => 0xffff, green => 0xffff, blue => 0xffff },
		},
		{
			NAME => 'Black on White',
			BG => { red => 0xffff, green => 0xffff, blue => 0xffff },
			FG => { red => 0x0000, green => 0x0000, blue => 0x0000 },
		},
		{
			NAME => 'White on Black',
			FG => { red => 0xffff, green => 0xffff, blue => 0xffff },
			BG => { red => 0x0000, green => 0x0000, blue => 0x0000 },
		},
		{
			NAME => 'White on Dark Blue',
			FG => { red => 0xffff, green => 0xffff, blue => 0xffff },
			BG => { red => 0x0000, green => 0x0000, blue => 0x8000 },
		},
	);
my $lastfontname = undef;

sub save_user_settings() {
	my $client = Gnome2::GConf::Client->get_default;
	my $app_key = "/apps/toilet_wrapper/prefs";
	my $font_name = $font_combo->get_active_text;

	$client->set($app_key . "/font", { type => 'string', value => $font_name });
	$client->set($app_key . "/theme", { type => 'string', value => $theme_name });

	return;
}

sub load_user_settings() {
	my $client = Gnome2::GConf::Client->get_default;
	my $app_key = "/apps/toilet_wrapper/prefs";
	
	$lastfontname = $client->get_string($app_key . "/font");
	$lastfontname = "bigmono9" unless $lastfontname;
	$theme_name = $client->get_string($app_key . "/theme");
	$theme_name = $themes[0]->{NAME} unless $theme_name;

#	print "$theme_name $lastfontname\n";

	return;
}

# Render text
sub render_text($$) {
	my $font_name = shift;
	my $textbuffer = $text_view->get_buffer;
	my $rendertext = shift;
	my $options = ""; #"-W";
	my $text = `toilet 2> /dev/null $options -w 1024 -f $font_name '$rendertext'`;
	$textbuffer->insert( $textbuffer->get_end_iter, decode("utf-8",$text) );
	$text_view->set_buffer($textbuffer);
}


#	Add user text to the text display widget
sub add_text() {
	my $font_name = $font_combo->get_active_text;
	my $entry_text = $user_text->get_text;
	render_text($font_name, $entry_text);
}

#	Copy the text from display widget to clipboard
sub on_clipbd_button_clicked() {
	my $textbuffer 	= $text_view->get_buffer;
	my $text 		= $textbuffer->get_text($textbuffer->get_start_iter, $textbuffer->get_end_iter, 0);
	my $clip 		= Gtk2::Clipboard->get(Gtk2::Gdk->SELECTION_CLIPBOARD);

	$clip->set_text($text);
}	

sub on_clear_button_clicked() {
	my $textbuffer = $text_view->get_buffer;
	$textbuffer->delete( $textbuffer->get_start_iter, $textbuffer->get_end_iter);
}

#	Handle selection of theme menu
sub on_menu_selected() {
	my ($mi, $ud) = (shift, shift);
	set_color_theme($ud);	
	return;
}

#	When user selects "Save" from menu display 'save as' dialog and write buffer
#	to file.
sub on_save1_activate() {
#	print "on_save1_activate()\n";
	my $chooser = Gtk2::FileChooserDialog->new ("Save as", undef, "save",
                                      'gtk-cancel' => 'cancel',
                                      'gtk-open' => 'ok');

	my $response = $chooser->run;

	if ($response eq 'ok') {
		my $filename 	= $chooser->get_filename;
		my $textbuffer 	= $text_view->get_buffer;
		my $text 		= $textbuffer->get_text($textbuffer->get_start_iter,
							$textbuffer->get_end_iter, 0);

#		print "Saving file $filename\n";

#	Save the buffer to file...
		open OFH, ">$filename";
		print OFH $text . "\n";
		close OFH;
	}

	$chooser->destroy;
	return;
}

sub on_button1_clicked() {
#	print "OK!\n";
	Gtk2->main_quit;
}

sub on_dialog1_destroy() {
#	print "destroy OK\n";
	Gtk2->main_quit;
}

sub on_go_button_clicked() {
#	print "clicked!\n";
	add_text;
}

# More 'civilized' way of getting font array than using 'find' 'basename' & 'sed'
sub get_font_array() {
	my @fontarray = ();

	sub wanted_file_proc() {
		my $filename = $_;
		my $fontname;

		if ($filename =~ /\.tlf$/) {
			$fontname = $filename;
			$fontname =~ s/\.tlf$//;
			push(@fontarray, $fontname);
		} elsif ($filename =~ /\.flf/) {
			$fontname = $filename;
			$fontname =~ s/\.flf$//;
			push(@fontarray, $fontname);
		}
	}

	find( { wanted => \&wanted_file_proc }, qw( /usr/share/figlet ) );
	@fontarray = sort @fontarray;

	return @fontarray;
}

# Use 'find' utility to locate all fonts in the figlets directory...
sub update_font_list() {
	@fonts = get_font_array;
}

#	Load fonts from font directory and update font combobox...
sub update_font_combo() {
	update_font_list;
	my $model = Gtk2::ListStore->new( 'Glib::String');
	my $i = 0;
	my $lastindex = 0;

	foreach my $fontname (sort @fonts) {
		$model->set( $model->append, 0, $fontname );

#	Determine if this is the last font used, store index if so...
		if ($fontname =~ /^$lastfontname/ ) {
			$lastindex = $i;	
		}
		$i++;
	}
	$font_combo->set_model($model);
	my  $renderer = Gtk2::CellRendererText->new;
	$font_combo->pack_start ($renderer, 1);
	$font_combo->add_attribute ($renderer, text => 0);
#	Set the active font to last index...
	$font_combo->set_active($lastindex);
}

sub on_quit_activate() {
	Gtk2->main_quit;
}

sub on_about_activate() {
	#print "about!\n";
	$aboutDialog->run;
	$aboutDialog->hide;
}

#	Set color theme to name
sub set_color_theme($) {
	my $theme 		= shift;

#	Find the theme in the array and get foreground & background colors
	for  (my $i = 0 ; $i < scalar @themes ; $i++) {
		if ($theme eq $themes[$i]->{NAME}) {
			my $bgcolor = Gtk2::Gdk::Color->new( $themes[$i]->{BG}->{red}, 
							$themes[$i]->{BG}->{green},
							$themes[$i]->{BG}->{blue} );
			my $textcolor = Gtk2::Gdk::Color->new( $themes[$i]->{FG}->{red}, 
							$themes[$i]->{FG}->{green},
							$themes[$i]->{FG}->{blue} );
#			print "found theme!\n";	
			
			$text_view->modify_base( 'normal', $bgcolor );
			$text_view->modify_text( 'normal', $textcolor );
			$theme_name = $theme;

			last;
		}
	}
}

#	Set the theme and font for the text view
sub set_textview_properties() {
	#print "set_textview_properties()\n");
	if (defined $text_view) {

		set_color_theme($theme_name);	# Set the color scheme according to theme

		# Set font to curier 10pt (required for proper viewing of monospaced fonts)
		my $font = Gtk2::Pango::FontDescription->from_string("Courier +9");
		$text_view->modify_font($font);
	}
}

#	Add the themes to the theme menu
sub setup_theme_menu() {
	my $mu = $glade->get_widget('menu3');

	for  (my $i = 0 ; $i < scalar @themes ; $i++) {
		my $themeName = $themes[$i]->{NAME};
		my $nm        = Gtk2::MenuItem->new( $themeName );

		$nm->signal_connect( activate =>\&on_menu_selected, $themeName);
		$nm->show;
		$mu->append($nm);
	}	
}

# When user hits 'return' in text widget render the text.
sub on_user_text_editing_done() {
	add_text;
}

# Generate gallery
sub on_gallery_activate() {
#	print "on_gallery_activate()\n";
	foreach my $fontname (sort @fonts) {
		render_text($fontname, $fontname);
	}
}

# Load user interface from .glade file
sub load_ui_from_glade($) {
	my $filepath = shift;
#	print "Loading from " . $filepath . "\n";

	if ( -f $filepath ) {
		$glade      = Gtk2::GladeXML->new( $filepath );
	} else {
		$glade = undef;
	}
}

# Load the UI from the Glade file, attempt to load from local directory in development
# environment

load_ui_from_glade("toilet_wrapper.glade");
if (not defined $glade) {
	load_ui_from_glade($install_prefix . "glade/toilet_wrapper.glade");
}

$mainwin    = $glade->get_widget('dialog1');
$text_view  = $glade->get_widget('text_view');
$user_text  = $glade->get_widget('user_text');
$font_combo = $glade->get_widget('font_combo');
$aboutDialog = $glade->get_widget('aboutDialog');

$aboutDialog->set_version($version);
# $mainwin->set_default_icon_from_file("/usr/share/toiletwrapper/pixmaps/Toilet_Wrapper.ico");

# Load last user settings and update font list
load_user_settings;
update_font_combo;

set_textview_properties;
setup_theme_menu;


# Show the dialog
$mainwin->show;

# Connect signals magically
$glade->signal_autoconnect_from_package('main');

$user_text->grab_focus; # set focus on text entry widget
Gtk2->main; # Start Gtk2 main loop

save_user_settings;

# that's it!

exit 0;


