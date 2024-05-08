<?php
/**
 */

namespace execut\crudFields\fields;


use detalika\requests\helpers\DateTimeHelper;
use kartik\daterange\DateRangePicker;
use kartik\detail\DetailView;
use yii\db\ActiveQuery;
use yii\helpers\ArrayHelper;

class Date extends Field
{
    public $isTime = false;
    public $fieldType = null;
    public $displayOnly = true;
    public function getColumn()
    {
        $parentColumn = parent::getColumn();
        if ($parentColumn === false) {
            return false;
        }

        $widgetOptions = $this->getWidgetOptions();

        return ArrayHelper::merge([
            'filter' => DateRangePicker::widget($widgetOptions),
            'format' => ['date', 'dd.MM.yy HH:mm'],
        ], $parentColumn);
    }

    public function getField()
    {
        if (empty($this->getValue()) && $this->displayOnly) {
            return false;
        }

        $field = parent::getField();
        if ($field === false) {
            return false;
        }

        if ($this->displayOnly) {
            return array_merge($field, [
                'displayOnly' => true,
                'format' => ['date', 'dd.MM.yy HH:mm'],
            ]);
        }

        if ($this->isTime) {
            $type = DetailView::INPUT_DATETIME;
        } else {
            $type = DetailView::INPUT_DATE;
        }

        if ($this->fieldType !== null) {
            $type = $this->fieldType;
        }

        return [
            'type' => $type,
            'attribute' => $this->attribute,
            'format' => ['date', 'dd.MM.yy HH:mm'],
            'widgetOptions' => $this->getWidgetOptions(),
        ];
    }

    public function getMultipleInputField()
    {
        if ($this->displayOnly) {
            return false;
        }

        return parent::getMultipleInputField(); // TODO: Change the autogenerated stub
    }

    public function applyScopes(ActiveQuery $query)
    {
        $modelClass = $query->modelClass;
        $attribute = $this->attribute;
        $t = $modelClass::tableName();
        $value = $this->model->$attribute;
        if (!empty($value) && strpos($value, ' - ') !== false) {
            $timeFormat = 'H:i:s';
            $dateTimeFormat = 'Y-m-d '. $timeFormat;

            list($from, $to) = explode(' - ', $value);
            if (!$this->isTime) {
                $from = $from . ' 00:00:00';
                $to = $to . ' 23:59:59';
            }

            $fromUtc = self::convertToUtc($from, $dateTimeFormat);
            $toUtc = self::convertToUtc($to, $dateTimeFormat);

            $query->andFilterWhere(['>=', $t . '.' . $attribute, $fromUtc])
                ->andFilterWhere(['<=', $t . '.' . $attribute, $toUtc]);
        }

        return $query;
    }

    public static function convertToUtc($dateTimeStr, $format)
    {
        $dateTime = \DateTime::createFromFormat(
            $format,
            $dateTimeStr,
            self::getApplicationTimeZone()
        );
        $dateTime->setTimezone(new \DateTimeZone(self::getDatabaseTimeZone()));
        return $dateTime->format($format);
    }

    protected static function getDatabaseTimeZone() {
        return 'Europe/Moscow';
    }

    private static function getApplicationTimeZone()
    {
        return (new \DateTimeZone(\Yii::$app->timeZone));
    }

    /**
     * @return array
     */
    protected function getWidgetOptions(): array
    {
        $format = $this->getFormat();
        $pluginOptions = [
            'format' => $this->getFormat(true),
            'locale' => ['format' => $format, 'separator' => ' - '],
            'todayHightlight' => true,
        ];

        if ($this->isTime) {
            $pluginOptions = ArrayHelper::merge($pluginOptions, [
                'timePicker' => true,
                'timePickerIncrement' => 15,
            ]);
        }

        $widgetOptions = [
            'attribute' => $this->attribute,
            'model' => $this->model,
            'convertFormat' => true,
            'pluginOptions' => $pluginOptions
        ];
        return $widgetOptions;
    }

    /**
     * @return string
     */
    protected function getFormat($forJs = false): string
    {
        if ($forJs) {
            $format = 'yyyy-MM-dd';
        } else {
            $format = 'Y-m-d';
        }

        if ($this->isTime) {
            if ($forJs) {
                $format .= ' H:i:s';
            } else {
                $format .= ' H:i:s';
            }
        }
        return $format;
    }
}