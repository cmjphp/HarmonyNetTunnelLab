import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      windowStage.loadContent('pages/Index');
    } catch (error) {
      console.error(`load page failed: ${JSON.stringify(error)}`);
    }
  }

  onWindowStageDestroy(): void {
  }

  onDestroy(): void {
  }
}
