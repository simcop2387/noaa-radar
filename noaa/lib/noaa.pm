package noaa;
use Dancer ':syntax';
use LWP::UserAgent;
use Data::Dumper;
use Image::Magick;
use HTTP::Date;

our $VERSION = '0.1';

my $ua = LWP::UserAgent->new();
 $ua->proxy(['http'], 'http://127.0.0.1:13128/');
# TODO setup a proxy thing here, i want to cache images that won't change from the NOAA, like the county images etc.

sub ua_get {
  my ($url) = @_;

  print STDERR "FETCH: $url\n";
  return undef if ($url =~ / /); # TODO naively check for it not being a url.  this is a result of the data I get from the URL
  
  my $resp = $ua->get($url);
         
  if (!$resp->is_success()) {
    status 'not_found';
    template 'special_404', { path => request->path };
  }
         
  return $resp->content();
}

sub gif_to_img {
  my ($data) = @_;
  my $img = Image::Magick->new();
  
  $img->BlobToImage($data);
  
  return $img;
}

sub img_to_gif {
   my ($img) = @_;
   my $data = $img->ImageToBlob(magick => "gif", loop=>0);
   
   return $data;
}

get '/noaa/:radarcode' => sub {
   my $noaa_base = 'http://radar.weather.gov/ridge/';
   my $tmp_dir = '/tmp/noaa_build';
   
   my $radarcode = lc params->{radarcode}; # make it lc since that's what noaa wants
   $radarcode =~ s/\.gif$//i;
   
   my $resp = $ua->get($noaa_base . $radarcode. '_NCR_overlayfiles.txt');

   if ($resp->is_success) {
     my $csv_data = $resp->content();
     # I'm going to go naive here, noaa shouldn't give me any funky data from what i'm seeing.
     
     my @image_content;
     
     for my $line (split /\n/, $csv_data) {
       my ($topo, $radar, $county, $rivers, $highway, $city, $warning, $legend) = map {s/\s+$//;s/^\s+//;ua_get($noaa_base.$_)} split /,/, $line;
       
       push @image_content, { #topo => $topo, # don't care about topo
                      radar => $radar, 
                      county => $county, 
                      rivers => $rivers, 
                      highway => $highway, 
                      city => $city, 
                      warning => $warning, 
                      legend => $legend};
     }
   
     my $gif_data;
   
     if (@image_content) {
       my $master_image = Image::Magick->new();
     
       $master_image->Set(loop => 1);
       
       for my $layer_hash (@image_content) {
         my ($radar, $county, $warning, $legend, $river, $city, $highway) = map {gif_to_img $_} @{$layer_hash}{qw(radar county warning legend rivers city highway)};
         my $img = Image::Magick->new();
         
         # filter noise from the radar
         for my $c (qw[rgb(3,0,244) rgb(1,159,244) rgb(4,233,231) rgb(100,100,100) rgb(153,153,102) rgb(204,204,153)]) {
           $radar->Opaque(fill => 'white', color => $c);
         }
         
         push @{$img}, $radar,
                       $county,
                       $highway,
                       $river,
                       $city,
                       $warning,
                       $legend;
         $img->Set(background => '#fff');
         $img = $img->Flatten();
         
         $img->Set(delay=>50);
         $img->Set(alpha=>"off");
         
         push @{$master_image}, $img;
       }
        
       $gif_data = img_to_gif($master_image);
     }
     
     header('Cache-Control' => 'max-age=600');
     header('Expires' => time2str(time()+600));
     header('Content-Type' => 'image/gif');
     return $gif_data;
   }
   
   status 'not_found';
   template 'special_404', { path => request->path };
};

true;
