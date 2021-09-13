#!/bin/bash

/usr/bin/python3 - $1 <<EOF
#
#  Podcasts Export
#  ---------------
#  Douglas Watson, 2020, MIT License
#
#  Intended for use within an Automator workflow.
#
#  Receives a destination folder, finds Apple Podcasts episodes that have been
#  downloaded, then copies those files into a new folder giving them a more
#  descriptive name.

import os
import sys
import shutil
import urllib.parse
import sqlite3

SQL = """
SELECT p.ZAUTHOR, p.ZTITLE, e.ZTITLE, e.ZITUNESSUBTITLE, e.ZASSETURL
from ZMTEPISODE e 
join ZMTPODCAST p
    on e.ZPODCASTUUID = p.ZUUID 
where ZASSETURL NOTNULL;
"""


def check_imports():
    """ Prompts for password to install dependencies, if needed """
    try:
        import mutagen
    except ImportError:
        os.system(
            """osascript -e 'do shell script "/usr/bin/pip3 install mutagen" with administrator privileges'""")


def get_downloaded_episodes(db_path):
    return sqlite3.connect(db_path).execute(SQL).fetchall()


def main(db_path, output_dir):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    for author, podcast, title, description, path in get_downloaded_episodes(db_path):
        safe_title = title.replace('/', '|').replace(':', ',')
        safe_podcast = podcast.replace('/', '|').replace(':', ',')
        safe_author = author.replace('/', '|').replace(':', ',')

        dest_path = os.path.join(output_dir,
                                 u"{}-{}-{}.mp3".format(safe_author, safe_podcast, safe_title))
        shutil.copy(urllib.parse.unquote(path[len('file://'):]), dest_path)

        try:
            mp3 = MP3(dest_path, ID3=EasyID3)
        except HeaderNotFoundError:
            print(u"Failed to export {} - {}: Corrupted file.".format(podcast, title))
            continue
        if mp3.tags is None:
            mp3.add_tags()
        mp3.tags['artist'] = author
        mp3.tags['album'] = podcast
        mp3.tags['title'] = title
        # Strip non-ascii characters and set - want to use non-ascii as well, so will construct tag object 'manually'
        # mp3.tags['comment'] = [description.encode('ascii',errors='ignore').decode('ascii')[:255]]
        mp3.save()
        # Tweak Comment Tag so it's visible in iTunes/Music
        ftag = ID3(dest_path)
        """
        #comment_key_name = next(x for x in ftag.keys() if x.startswith('COMM'))
        comment_key = ftag.getall('COMM')[0]
        comment_key_name = f"{comment_key.FrameID}::{comment_key.lang}"
        # Encoding to LATIN1, default is UTF8
        ftag[comment_key_name].encoding=0 
        # Language to English, default is XXX
        ftag[comment_key_name].lang='eng'
        """
        # remove all comment tags just in case
        '''
        # check comment tags
        ftag.getall('COMM')
        '''
        ftag.delall('COMM')

        #construct comment object
        new_comm = COMM(encoding=Encoding.UTF16, lang='eng', text=[description[:255]])
        ftag.add(new_comm)

        # save file again to fix ID3 tag
        ftag.save()


if __name__ == "__main__":
    if len(sys.argv) <= 1:
        sys.stderr.write("No output folder specified\n")
        sys.exit(1)
    output_dir = sys.argv[1]
    db_path = os.path.expanduser(
        "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite")

    check_imports()
    from mutagen.mp3 import MP3, HeaderNotFoundError
    from mutagen.easyid3 import EasyID3
    '''
    # Register comment tag - produces broken comment that does not display in iTunes/Music, will construct manually instead
    EasyID3.RegisterTextKey('comment', 'COMM')
    '''
    # Instead, Import ID3 Class for Post-Edits
    from mutagen.id3 import ID3,COMM,Encoding
    main(db_path, output_dir)
EOF
