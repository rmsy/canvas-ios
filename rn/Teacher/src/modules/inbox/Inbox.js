import React, { Component } from 'react'
import {
  View,
  Text,
} from 'react-native'
import i18n from 'format-message'

export default class Inbox extends Component {

  render (): React.Element<{}> {
    return (
      <View>
        <Text>{i18n('This is the inbox')}</Text>
      </View>
    )
  }
}
