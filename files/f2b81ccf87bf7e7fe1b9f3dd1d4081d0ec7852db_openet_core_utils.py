import calendar
import datetime
import logging
from time import sleep

import ee


def getinfo(ee_obj, n=4):
    """Make an exponential back off getInfo call on an Earth Engine object"""
    output = None
    for i in range(1, n):
        try:
            output = ee_obj.getInfo()
        except ee.ee_exception.EEException as e:
            if 'Earth Engine memory capacity exceeded' in str(e):
                logging.info('    Resending query ({}/10)'.format(i))
                logging.debug('    {}'.format(e))
                sleep(i ** 2)
            else:
                raise e

        if output:
            break

    # output = ee_obj.getInfo()
    return output


# TODO: Import from common.utils
# Should these be test fixtures instead?
# I'm not sure how to make them fixtures and allow input parameters
def constant_image_value(image, crs='EPSG:32613', scale=1):
    """Extract the output value from a calculation done with constant images"""
    return getinfo(ee.Image(image).reduceRegion(
        reducer=ee.Reducer.first(), scale=scale,
        geometry=ee.Geometry.Rectangle([0, 0, 10, 10], crs, False)))


def point_image_value(image, xy, scale=1):
    """Extract the output value from a calculation at a point"""
    return getinfo(ee.Image(image).reduceRegion(
        reducer=ee.Reducer.first(), geometry=ee.Geometry.Point(xy),
        scale=scale))


def point_coll_value(coll, xy, scale=1):
    """Extract the output value from a calculation at a point"""
    output = getinfo(coll.getRegion(ee.Geometry.Point(xy), scale=scale))

    # Structure output to easily be converted to a Pandas dataframe
    # First key is band name, second key is the date string
    col_dict = {}
    info_dict = {}
    for i, k in enumerate(output[0][4:]):
        col_dict[k] = i + 4
        info_dict[k] = {}
    for row in output[1:]:
        date = datetime.datetime.utcfromtimestamp(row[3] / 1000.0).strftime(
            '%Y-%m-%d')
        for k, v in col_dict.items():
            info_dict[k][date] = row[col_dict[k]]
    return info_dict
    # return pd.DataFrame.from_dict(info_dict)


def millis(input_dt):
    """Convert datetime to milliseconds since epoch

    Parameters
    ----------
    input_df : datetime

    Returns
    -------
    int

    """
    return 1000 * int(calendar.timegm(input_dt.timetuple()))


def date_0utc(date):
    """Get the 0 UTC date for a date

    Parameters
    ----------
    date : ee.Date

    Returns
    -------
    ee.Date

    """
    return ee.Date.fromYMD(date.get('year'), date.get('month'),
                           date.get('day'))

    # Extra operations are needed since update() does not set milliseconds to 0.
    # return ee.Date(date.update(hour=0, minute=0, second=0).millis()\
    #     .divide(1000).floor().multiply(1000))
