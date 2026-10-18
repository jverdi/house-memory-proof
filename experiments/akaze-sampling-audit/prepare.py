"""Fifth bounded finished-384 repair attempt; never patch the shipped detector.

Apply exactly one fixed 2x cubic analysis resize, capped by the existing 1280px
analysis budget. Keep descriptor, spatial, availability and ambiguity gates.
The existing integer-pixel-centre adapter restores original-image coordinates.
"""
from pathlib import Path


def prepare(path):
    source=path.read_text()
    before='double scale=std::min(1.0,1280.0/std::max(w,h));cv::resize(source,image,cv::Size(),scale,scale,cv::INTER_AREA);'
    after='double scale=std::min(2.0,1280.0/std::max(w,h));cv::resize(source,image,cv::Size(),scale,scale,scale>1.0 ? cv::INTER_CUBIC:cv::INTER_AREA);'
    if source.count(before)!=1:
        raise ValueError('The expected production sampling adapter changed; refuse the experiment patch')
    path.write_text(source.replace(before,after))


if __name__=='__main__':
    prepare(Path('packages/visual-core/hx_vision.cpp'))
    print('Prepared one fixed 2x AKAZE analysis-sampling experiment; all gates unchanged')
